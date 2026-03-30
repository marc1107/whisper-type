import AVFoundation
import Foundation

final class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var samples: [Float] = []
    private let samplesLock = NSLock()
    private let targetSampleRate: Double = 16000

    var isRecording: Bool { audioEngine?.isRunning ?? false }

    func startRecording() throws {
        samples = []
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.converterCreationFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        engine.prepare()
        try engine.start()
        self.audioEngine = engine
    }

    func stopRecording() -> [Float] {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        samplesLock.lock()
        let result = samples
        samples = []
        samplesLock.unlock()
        return result
    }

    private func processBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard frameCount > 0,
              let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount)
        else { return }

        var error: NSError?
        var inputConsumed = false
        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil, let channelData = convertedBuffer.floatChannelData else { return }
        let count = Int(convertedBuffer.frameLength)

        samplesLock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: count))
        samplesLock.unlock()
    }
}

enum AudioRecorderError: LocalizedError {
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .converterCreationFailed:
            return "Audio-Konverter konnte nicht erstellt werden."
        }
    }
}
