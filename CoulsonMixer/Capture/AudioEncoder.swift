import Foundation
import AVFAudio
import AudioToolbox

#if os(macOS)

/// Encodes captured PCM into ADTS-framed AAC packets suitable for a live HTTP byte stream.
/// Pure CPU work with no UI ties, so it stays off the module's default MainActor isolation.
nonisolated final class AudioEncoder {
    private let converter: AVAudioConverter
    private let channelCount: UInt32
    let outputFormat: AVAudioFormat

    init?(inputFormat: AVAudioFormat) {
        let channelCount = min(inputFormat.channelCount, 2)
        var aacASBD = AudioStreamBasicDescription(
            mSampleRate: inputFormat.sampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: channelCount,
            mBitsPerChannel: 0,
            mReserved: 0
        )
        guard let compressedFormat = AVAudioFormat(streamDescription: &aacASBD),
              let converter = AVAudioConverter(from: inputFormat, to: compressedFormat) else {
            return nil
        }
        self.converter = converter
        self.channelCount = channelCount
        self.outputFormat = compressedFormat
    }

    /// Feeds one captured buffer to the converter and drains every complete AAC packet it can
    /// produce right now. The converter instance persists frames between calls, so a buffer
    /// shorter than one AAC frame (1024 samples) legitimately yields zero packets.
    func encode(_ pcmBuffer: AVAudioPCMBuffer) -> [Data] {
        var packets: [Data] = []
        var hasSuppliedInput = false

        while true {
            let output = AVAudioCompressedBuffer(format: outputFormat, packetCapacity: 8, maximumPacketSize: 4096)
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                if hasSuppliedInput {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                hasSuppliedInput = true
                inputStatus.pointee = .haveData
                return pcmBuffer
            }

            guard status == .haveData, output.packetCount > 0 else { break }

            let byteCount = Int(output.byteLength)
            let payload = Data(bytes: output.data, count: byteCount)
            let header = ADTSHeaderWriter.header(
                packetLength: byteCount,
                sampleRate: outputFormat.sampleRate,
                channelCount: Int(channelCount)
            )
            packets.append(header + payload)
        }

        return packets
    }
}

/// Builds the 7-byte ADTS header each AAC packet needs so a raw elemental stream (no MP4/CAF
/// container) can be parsed mid-stream by an HTTP client, including Safari's <audio> element.
enum ADTSHeaderWriter {
    private static let sampleRateTable: [Double] = [
        96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350
    ]

    static func header(packetLength: Int, sampleRate: Double, channelCount: Int) -> Data {
        let profile = 2 // AAC-LC
        let frequencyIndex = sampleRateTable.firstIndex { abs($0 - sampleRate) < 1 } ?? 4
        let frameLength = packetLength + 7

        var header = [UInt8](repeating: 0, count: 7)
        header[0] = 0xFF
        header[1] = 0xF1
        header[2] = UInt8((profile - 1) << 6) | UInt8((frequencyIndex & 0x0F) << 2) | UInt8((channelCount >> 2) & 0x1)
        header[3] = UInt8((channelCount & 0x3) << 6) | UInt8((frameLength >> 11) & 0x3)
        header[4] = UInt8((frameLength >> 3) & 0xFF)
        header[5] = UInt8((frameLength & 0x7) << 5) | 0x1F
        header[6] = 0xFC
        return Data(header)
    }
}

#endif
