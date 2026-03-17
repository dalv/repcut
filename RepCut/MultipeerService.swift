import Foundation
import MultipeerConnectivity
import AVFoundation
import VideoToolbox

// MARK: - Connection State

enum ConnectionState: Equatable {
    case idle
    case advertising
    case browsing
    case connecting
    case connected(peerName: String)
}

// MARK: - Packet Types

private enum PacketType: UInt8 {
    case videoKeyframe = 0x01
    case videoPFrame   = 0x02
    case audio         = 0x03
}

// MARK: - Timestamped Frame (compressed)

struct TimestampedFrame {
    let compressedData: Data
    let timestamp: TimeInterval
    let isKeyframe: Bool
}

struct TimestampedAudio {
    let data: Data
    let timestamp: TimeInterval
}

// MARK: - Circular Buffer

struct CircularBuffer<T> {
    private var storage: [T?]
    private(set) var count = 0
    private var writeIndex = 0
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    mutating func append(_ item: T) {
        storage[writeIndex] = item
        writeIndex = (writeIndex + 1) % capacity
        if count < capacity { count += 1 }
    }

    /// Access item by age: 0 = most recent, 1 = second most recent, etc.
    func item(atAge age: Int) -> T? {
        guard age >= 0, age < count else { return nil }
        let index = (writeIndex - 1 - age + capacity * 2) % capacity
        return storage[index]
    }

    mutating func removeAll() {
        storage = Array(repeating: nil, count: capacity)
        count = 0
        writeIndex = 0
    }

    /// Returns all items from oldest to newest
    var allItems: [T] {
        var result: [T] = []
        for i in stride(from: count - 1, through: 0, by: -1) {
            if let item = item(atAge: i) {
                result.append(item)
            }
        }
        return result
    }
}

// MARK: - MultipeerService

class MultipeerService: NSObject, ObservableObject {
    static let serviceType = "repcut"

    @Published var connectionState: ConnectionState = .idle
    @Published var connectedPeers: [MCPeerID] = []
    @Published var availablePeers: [MCPeerID] = []

    private let myPeerID: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    // Streams
    private var videoOutputStreams: [MCPeerID: OutputStream] = [:]
    private var audioOutputStreams: [MCPeerID: OutputStream] = [:]
    private let streamQueue = DispatchQueue(label: "com.repcut.stream", qos: .userInitiated)

    // H.264 Encoder
    private var compressionSession: VTCompressionSession?
    private var encoderReady = false
    private var sessionStartTime: TimeInterval = 0

    // H.264 Decoder
    private var decompressionSession: VTDecompressionSession?
    private var formatDescription: CMFormatDescription?

    // Callbacks for viewer
    var onFrameReceived: ((CVPixelBuffer, TimeInterval) -> Void)?
    var onCompressedFrameReceived: ((TimestampedFrame) -> Void)?
    var onAudioReceived: ((TimestampedAudio) -> Void)?

    // Input stream reading
    private var videoInputThread: Thread?
    private var audioInputThread: Thread?
    private var videoInputStream: InputStream?
    private var audioInputStream: InputStream?

    override init() {
        self.myPeerID = MCPeerID(displayName: Self.deviceDisplayName())
        super.init()
        self.session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .none)
        self.session.delegate = self
    }

    /// Returns a user-friendly device name similar to AirDrop.
    /// iOS 16+ restricts UIDevice.current.name to generic "iPhone" without a special entitlement.
    /// The system hostname (e.g. "Vlads-iPhone.local") still contains the user-assigned name,
    /// so we parse it to reconstruct "Vlad's iPhone".
    private static func deviceDisplayName() -> String {
        let deviceName = UIDevice.current.name
        // If UIDevice already returns a personalized name, use it
        let model = UIDevice.current.model // "iPhone", "iPad"
        if deviceName != model {
            return deviceName
        }
        // Fall back to hostname parsing
        var hostname = ProcessInfo.processInfo.hostName
        // Remove .local suffix
        if hostname.hasSuffix(".local") {
            hostname = String(hostname.dropLast(6))
        }
        // "Vlads-iPhone" → "Vlad's iPhone"
        if let dashRange = hostname.range(of: "-\(model)", options: .caseInsensitive) {
            let ownerPart = String(hostname[hostname.startIndex..<dashRange.lowerBound])
            if !ownerPart.isEmpty {
                // Add possessive apostrophe: "Vlads" → "Vlad's"
                var owner = ownerPart
                if owner.lowercased().hasSuffix("s") {
                    owner = String(owner.dropLast()) + "'s"
                }
                return "\(owner) \(model)"
            }
        }
        return deviceName
    }

    deinit {
        stopAdvertising()
        stopBrowsing()
        teardownEncoder()
        teardownDecoder()
    }

    // MARK: - Advertiser (Broadcaster)

    func startAdvertising() {
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: Self.serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        DispatchQueue.main.async { self.connectionState = .advertising }
    }

    func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        closeAllStreams()
        // Set state directly — this is always called from main thread
        if case .advertising = connectionState { connectionState = .idle }
        else if case .connected = connectionState { connectionState = .idle }
    }

    // MARK: - Browser (Viewer)

    func startBrowsing() {
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        connectionState = .browsing
        availablePeers = []
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
        videoInputThread?.cancel()
        audioInputThread?.cancel()
        if case .browsing = connectionState { connectionState = .idle }
        else if case .connected = connectionState { connectionState = .idle }
        availablePeers = []
    }

    func connectToPeer(_ peer: MCPeerID) {
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 10)
        DispatchQueue.main.async { self.connectionState = .connecting }
    }

    func disconnect() {
        closeAllStreams()
        // Disconnect MCSession on a background thread — it can block
        let sessionRef = session!
        DispatchQueue.global(qos: .utility).async {
            sessionRef.disconnect()
        }
        connectionState = .idle
        connectedPeers = []
    }

    // MARK: - H.264 Encoder Setup

    func setupEncoder(width: Int32, height: Int32) {
        teardownEncoder()
        sessionStartTime = CACurrentMediaTime()

        let callback: VTCompressionOutputCallback = { refcon, _, status, _, sampleBuffer in
            guard status == noErr, let sampleBuffer = sampleBuffer, let refcon = refcon else { return }
            let service = Unmanaged<MultipeerService>.fromOpaque(refcon).takeUnretainedValue()
            service.handleEncodedFrame(sampleBuffer)
        }

        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: callback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &compressionSession
        )

        guard status == noErr, let session = compressionSession else {
            print("Failed to create compression session: \(status)")
            return
        }

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: 1_500_000 as CFNumber)
        // Keyframe every 0.5 seconds for fast recovery from drops
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 15 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 0.5 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)

        VTCompressionSessionPrepareToEncodeFrames(session)
        encoderReady = true
    }

    func teardownEncoder() {
        if let session = compressionSession {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
        compressionSession = nil
        encoderReady = false
    }

    // MARK: - Send Video Frame

    func sendVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard encoderReady, let compressionSession = compressionSession else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        VTCompressionSessionEncodeFrame(
            compressionSession,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }

    private func handleEncodedFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        let isKeyframe: Bool
        if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false),
           CFArrayGetCount(attachmentsArray) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachmentsArray, 0), to: CFDictionary.self)
            var notSyncValue: UnsafeRawPointer?
            let hasKey = CFDictionaryGetValueIfPresent(dict, unsafeBitCast(kCMSampleAttachmentKey_NotSync, to: UnsafeRawPointer.self), &notSyncValue)
            if hasKey, let val = notSyncValue {
                isKeyframe = !CFBooleanGetValue(unsafeBitCast(val, to: CFBoolean.self))
            } else {
                // Key not present means it IS a sync frame (keyframe)
                isKeyframe = true
            }
        } else {
            isKeyframe = true
        }

        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)

        guard let pointer = dataPointer, totalLength > 0 else { return }

        var packetData = Data()

        // For keyframes, prepend SPS/PPS from format description
        if isKeyframe {
            print("[MultipeerService] Encoding KEYFRAME, size: \(totalLength)")
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                packetData.append(extractParameterSets(from: formatDesc))
            }
        }

        // Convert AVCC (length-prefixed) to Annex B (start code prefixed)
        var offset = 0
        let startCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]
        while offset < totalLength {
            var naluLength: UInt32 = 0
            memcpy(&naluLength, pointer + offset, 4)
            naluLength = naluLength.bigEndian
            offset += 4

            packetData.append(contentsOf: startCode)
            packetData.append(Data(bytes: pointer + offset, count: Int(naluLength)))
            offset += Int(naluLength)
        }

        let timestamp = CACurrentMediaTime() - sessionStartTime
        let packetType: PacketType = isKeyframe ? .videoKeyframe : .videoPFrame
        writePacket(type: packetType, timestamp: timestamp, payload: packetData)
    }

    private func extractParameterSets(from formatDescription: CMFormatDescription) -> Data {
        var data = Data()
        let startCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]

        // SPS
        var spsSize = 0
        var spsCount = 0
        var spsPointer: UnsafePointer<UInt8>?
        if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, parameterSetIndex: 0, parameterSetPointerOut: &spsPointer, parameterSetSizeOut: &spsSize, parameterSetCountOut: &spsCount, nalUnitHeaderLengthOut: nil) == noErr,
           let sps = spsPointer {
            data.append(contentsOf: startCode)
            data.append(sps, count: spsSize)
        }

        // PPS
        var ppsSize = 0
        var ppsPointer: UnsafePointer<UInt8>?
        if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, parameterSetIndex: 1, parameterSetPointerOut: &ppsPointer, parameterSetSizeOut: &ppsSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr,
           let pps = ppsPointer {
            data.append(contentsOf: startCode)
            data.append(pps, count: ppsSize)
        }

        return data
    }

    // MARK: - Send Audio

    func sendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)

        guard let pointer = dataPointer, totalLength > 0 else { return }

        let audioData = Data(bytes: pointer, count: totalLength)
        let timestamp = CACurrentMediaTime() - sessionStartTime
        writePacket(type: .audio, timestamp: timestamp, payload: audioData)
    }

    // MARK: - Stream Protocol

    /// Writes a length-prefixed packet to all connected output streams.
    /// Format: [1B type][8B timestamp][4B length][payload]
    private func writePacket(type: PacketType, timestamp: TimeInterval, payload: Data) {
        let streams: [OutputStream]
        if type == .audio {
            streams = Array(audioOutputStreams.values)
        } else {
            streams = Array(videoOutputStreams.values)
        }
        guard !streams.isEmpty else { return }

        var header = Data(count: 13)
        header[0] = type.rawValue
        var ts = timestamp
        header.replaceSubrange(1..<9, with: Data(bytes: &ts, count: 8))
        var len = UInt32(payload.count).bigEndian
        header.replaceSubrange(9..<13, with: Data(bytes: &len, count: 4))

        let fullPacket = header + payload

        streamQueue.async {
            for stream in streams {
                fullPacket.withUnsafeBytes { buffer in
                    guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                    var bytesWritten = 0
                    let total = fullPacket.count
                    while bytesWritten < total {
                        let result = stream.write(ptr + bytesWritten, maxLength: total - bytesWritten)
                        if result <= 0 { break }
                        bytesWritten += result
                    }
                }
            }
        }
    }

    // MARK: - Stream Reading (Viewer)

    private func startReadingStream(_ inputStream: InputStream, isVideo: Bool) {
        let thread = Thread { [weak self] in
            inputStream.schedule(in: .current, forMode: .default)
            inputStream.open()

            var headerBuffer = Data(count: 13)
            let runLoop = RunLoop.current

            while !Thread.current.isCancelled {
                runLoop.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))

                // Check stream status — bail if closed, errored, or at end
                let status = inputStream.streamStatus
                if status == .closed || status == .error || status == .atEnd {
                    break
                }

                guard inputStream.hasBytesAvailable else { continue }

                // Read header — break on failure (stream closed/error)
                guard self?.readExact(from: inputStream, into: &headerBuffer, count: 13) == true else { break }

                let typeByte = headerBuffer[0]
                guard let packetType = PacketType(rawValue: typeByte) else { continue }

                var ts: TimeInterval = 0
                headerBuffer.withUnsafeBytes { buffer in
                    let ptr = buffer.baseAddress!
                    memcpy(&ts, ptr + 1, 8)
                }

                var lengthBE: UInt32 = 0
                headerBuffer.withUnsafeBytes { buffer in
                    let ptr = buffer.baseAddress!
                    memcpy(&lengthBE, ptr + 9, 4)
                }
                let payloadLength = Int(UInt32(bigEndian: lengthBE))

                guard payloadLength > 0, payloadLength < 10_000_000 else { continue }

                var payload = Data(count: payloadLength)
                guard self?.readExact(from: inputStream, into: &payload, count: payloadLength) == true else { break }

                switch packetType {
                case .videoKeyframe:
                    let frame = TimestampedFrame(compressedData: payload, timestamp: ts, isKeyframe: true)
                    self?.onCompressedFrameReceived?(frame)
                case .videoPFrame:
                    let frame = TimestampedFrame(compressedData: payload, timestamp: ts, isKeyframe: false)
                    self?.onCompressedFrameReceived?(frame)
                case .audio:
                    let audio = TimestampedAudio(data: payload, timestamp: ts)
                    self?.onAudioReceived?(audio)
                }
            }

            inputStream.close()
        }

        thread.qualityOfService = .userInitiated
        thread.name = isVideo ? "com.repcut.videoInput" : "com.repcut.audioInput"
        thread.start()

        if isVideo {
            videoInputThread = thread
            videoInputStream = inputStream
        } else {
            audioInputThread = thread
            audioInputStream = inputStream
        }
    }

    private func readExact(from stream: InputStream, into data: inout Data, count: Int) -> Bool {
        var totalRead = 0
        while totalRead < count {
            let bytesRead = data.withUnsafeMutableBytes { buffer -> Int in
                guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
                return stream.read(ptr + totalRead, maxLength: count - totalRead)
            }
            if bytesRead <= 0 { return false }
            totalRead += bytesRead
        }
        return true
    }

    // MARK: - H.264 Decoder

    func decodeFrame(_ frame: TimestampedFrame) -> CVPixelBuffer? {
        let data = frame.compressedData

        // Parse Annex B NAL units
        let nalUnits = parseAnnexBNALUnits(data)

        var spsData: Data?
        var ppsData: Data?
        var sliceData: Data?

        for nalu in nalUnits {
            guard !nalu.isEmpty else { continue }
            let naluType = nalu[0] & 0x1F
            switch naluType {
            case 7: spsData = nalu  // SPS
            case 8: ppsData = nalu  // PPS
            case 1, 5: sliceData = nalu  // Coded slice / IDR slice
            default: break
            }
        }

        // Create format description from SPS/PPS if available
        if let sps = spsData, let pps = ppsData {
            var newFormatDesc: CMFormatDescription?

            let status = sps.withUnsafeBytes { spsBuffer -> OSStatus in
                pps.withUnsafeBytes { ppsBuffer -> OSStatus in
                    var pointers: [UnsafePointer<UInt8>] = [
                        spsBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        ppsBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    ]
                    var sizes = [sps.count, pps.count]
                    return pointers.withUnsafeMutableBufferPointer { ptrsBuffer in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 2,
                            parameterSetPointers: ptrsBuffer.baseAddress!,
                            parameterSetSizes: &sizes,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &newFormatDesc
                        )
                    }
                }
            }

            if status == noErr, let desc = newFormatDesc {
                if formatDescription == nil || !CMFormatDescriptionEqual(desc, otherFormatDescription: formatDescription!) {
                    formatDescription = desc
                    print("[MultipeerService] Created H.264 format description, setting up decoder")
                    setupDecoder(formatDescription: desc)
                }
            } else {
                print("[MultipeerService] Failed to create format description, status: \(status)")
            }
        }

        // Decode the slice
        guard let slice = sliceData, let fmtDesc = formatDescription else { return nil }

        // Convert Annex B to AVCC format (length-prefixed)
        var avccData = Data()
        var naluLen = UInt32(slice.count).bigEndian
        avccData.append(Data(bytes: &naluLen, count: 4))
        avccData.append(slice)

        let avccLength = avccData.count
        var blockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: avccLength,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avccLength,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        if let bb = blockBuffer {
            avccData.withUnsafeBytes { rawBuffer in
                guard let ptr = rawBuffer.baseAddress else { return }
                CMBlockBufferReplaceDataBytes(with: ptr, blockBuffer: bb, offsetIntoDestination: 0, dataLength: avccLength)
            }
        }

        guard let bb = blockBuffer else { return nil }

        var sampleBuffer: CMSampleBuffer?
        var sampleSize = avccData.count
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(seconds: frame.timestamp, preferredTimescale: 600),
            decodeTimeStamp: .invalid
        )
        CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: bb,
            formatDescription: fmtDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard let sb = sampleBuffer, let decompSession = decompressionSession else { return nil }

        var outputPixelBuffer: CVPixelBuffer?
        var flagsOut = VTDecodeInfoFlags()

        VTDecompressionSessionDecodeFrame(
            decompSession,
            sampleBuffer: sb,
            flags: [],  // Synchronous decode — callback fires before this returns
            frameRefcon: nil,
            infoFlagsOut: &flagsOut
        )

        // The decoded frame is delivered via the callback set in setupDecoder
        return nil // Frames delivered via onFrameReceived callback
    }

    /// Invalidates the current decoder so the next keyframe sets up a fresh one.
    func resetDecoder() {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
        }
        decompressionSession = nil
        formatDescription = nil
    }

    private func setupDecoder(formatDescription: CMFormatDescription) {
        if let old = decompressionSession {
            VTDecompressionSessionInvalidate(old)
        }

        let decoderConfig: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { refcon, _, status, _, imageBuffer, pts, _ in
                guard status == noErr, let pixelBuffer = imageBuffer else { return }
                let service = Unmanaged<MultipeerService>.fromOpaque(refcon!).takeUnretainedValue()
                let timestamp = CMTimeGetSeconds(pts)
                // Call directly — don't dispatch to main to avoid deadlock
                // with VTDecompressionSessionWaitForAsynchronousFrames
                service.onFrameReceived?(pixelBuffer, timestamp)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        let decoderStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: decoderConfig as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &decompressionSession
        )
        print("[MultipeerService] Decoder setup status: \(decoderStatus), session: \(decompressionSession != nil)")
    }

    func teardownDecoder() {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
        }
        decompressionSession = nil
        formatDescription = nil
    }

    // MARK: - NAL Unit Parsing

    private func parseAnnexBNALUnits(_ data: Data) -> [Data] {
        var nalUnits: [Data] = []
        var i = 0
        let bytes = [UInt8](data)
        let count = bytes.count

        while i < count {
            // Find start code (0x00 0x00 0x00 0x01 or 0x00 0x00 0x01)
            var startCodeLen = 0
            if i + 3 < count && bytes[i] == 0 && bytes[i+1] == 0 && bytes[i+2] == 0 && bytes[i+3] == 1 {
                startCodeLen = 4
            } else if i + 2 < count && bytes[i] == 0 && bytes[i+1] == 0 && bytes[i+2] == 1 {
                startCodeLen = 3
            } else {
                i += 1
                continue
            }

            let naluStart = i + startCodeLen
            i = naluStart

            // Find next start code
            while i < count {
                if i + 3 < count && bytes[i] == 0 && bytes[i+1] == 0 && bytes[i+2] == 0 && bytes[i+3] == 1 {
                    break
                } else if i + 2 < count && bytes[i] == 0 && bytes[i+1] == 0 && bytes[i+2] == 1 {
                    break
                }
                i += 1
            }

            if naluStart < i {
                nalUnits.append(Data(bytes[naluStart..<i]))
            }
        }

        return nalUnits
    }

    // MARK: - Stream Management

    private func openStreamsTo(_ peer: MCPeerID) {
        do {
            let videoStream = try session.startStream(withName: "video", toPeer: peer)
            videoStream.schedule(in: .main, forMode: .default)
            videoStream.open()
            videoOutputStreams[peer] = videoStream

            let audioStream = try session.startStream(withName: "audio", toPeer: peer)
            audioStream.schedule(in: .main, forMode: .default)
            audioStream.open()
            audioOutputStreams[peer] = audioStream
        } catch {
            print("Failed to open streams to \(peer.displayName): \(error)")
        }
    }

    private func closeAllStreams() {
        for stream in videoOutputStreams.values { stream.close() }
        for stream in audioOutputStreams.values { stream.close() }
        videoOutputStreams.removeAll()
        audioOutputStreams.removeAll()

        // Close input streams first to unblock any read() calls,
        // then cancel the threads
        videoInputStream?.close()
        audioInputStream?.close()
        videoInputStream = nil
        audioInputStream = nil
        videoInputThread?.cancel()
        audioInputThread?.cancel()
        videoInputThread = nil
        audioInputThread = nil
    }
}

// MARK: - MCSessionDelegate

extension MultipeerService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.connectedPeers = session.connectedPeers
            switch state {
            case .connected:
                self.connectionState = .connected(peerName: peerID.displayName)
                // If we're advertising (broadcaster), open streams to viewer
                if self.advertiser != nil {
                    self.openStreamsTo(peerID)
                }
            case .notConnected:
                self.videoOutputStreams.removeValue(forKey: peerID)?.close()
                self.audioOutputStreams.removeValue(forKey: peerID)?.close()
                if session.connectedPeers.isEmpty {
                    if self.advertiser != nil {
                        self.connectionState = .advertising
                    } else if self.browser != nil {
                        self.connectionState = .browsing
                    } else {
                        self.connectionState = .idle
                    }
                }
            case .connecting:
                self.connectionState = .connecting
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Not used — we use streams instead
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        startReadingStream(stream, isVideo: streamName == "video")
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept connections (trusted local network)
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Failed to advertise: \(error)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            if !self.availablePeers.contains(where: { $0.displayName == peerID.displayName }) {
                self.availablePeers.append(peerID)
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.availablePeers.removeAll { $0.displayName == peerID.displayName }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("Failed to browse: \(error)")
    }
}

