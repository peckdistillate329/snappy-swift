import XCTest
@testable import SnappySwift
import Foundation

/// Performance benchmarks for Snappy compression/decompression
///
/// Note: Some benchmarks use random data for incompressible test cases.
/// Results may vary between runs due to randomness, which is acceptable
/// for local performance checks but should be considered if used in
/// automated reporting or CI/CD pipelines.
final class BenchmarkTests: XCTestCase {

    // MARK: - Compression Benchmarks

    func testCompressBenchmark_1KB_Compressible() throws {
        let data = Data(repeating: 0x41, count: 1024)  // 1KB of 'A's

        measure {
            _ = try! data.snappyCompressed()
        }
    }

    func testCompressBenchmark_10KB_Compressible() throws {
        let data = Data(repeating: 0x41, count: 10 * 1024)  // 10KB of 'A's

        measure {
            _ = try! data.snappyCompressed()
        }
    }

    func testCompressBenchmark_100KB_Compressible() throws {
        let data = Data(repeating: 0x41, count: 100 * 1024)  // 100KB of 'A's

        measure {
            _ = try! data.snappyCompressed()
        }
    }

    func testCompressBenchmark_1MB_Compressible() throws {
        let data = Data(repeating: 0x41, count: 1024 * 1024)  // 1MB of 'A's

        measure {
            _ = try! data.snappyCompressed()
        }
    }

    func testCompressBenchmark_1KB_Incompressible() throws {
        // Random data (incompressible)
        var data = Data(count: 1024)
        data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for i in 0..<1024 {
                bytes[i] = UInt8.random(in: 0...255)
            }
        }

        measure {
            _ = try! data.snappyCompressed()
        }
    }

    func testCompressBenchmark_10KB_Incompressible() throws {
        var data = Data(count: 10 * 1024)
        data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for i in 0..<(10 * 1024) {
                bytes[i] = UInt8.random(in: 0...255)
            }
        }

        measure {
            _ = try! data.snappyCompressed()
        }
    }

    func testCompressBenchmark_100KB_Incompressible() throws {
        var data = Data(count: 100 * 1024)
        data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for i in 0..<(100 * 1024) {
                bytes[i] = UInt8.random(in: 0...255)
            }
        }

        measure {
            _ = try! data.snappyCompressed()
        }
    }

    func testCompressBenchmark_1KB_MixedPattern() throws {
        // Mixed: some repetition, some unique
        var data = Data()
        for _ in 0..<32 {
            data.append(contentsOf: "The quick brown fox ".utf8)  // 20 bytes repeated
            data.append(contentsOf: (0..<12).map { _ in UInt8.random(in: 0...255) })  // 12 random bytes
        }

        measure {
            _ = try! data.snappyCompressed()
        }
    }

    func testCompressBenchmark_10KB_MixedPattern() throws {
        var data = Data()
        for i in 0..<100 {
            data.append(contentsOf: "Line \(i): Lorem ipsum dolor sit amet. ".utf8)
            data.append(contentsOf: (0..<50).map { _ in UInt8.random(in: 0...255) })
        }

        measure {
            _ = try! data.snappyCompressed()
        }
    }

    // MARK: - Decompression Benchmarks

    func testDecompressBenchmark_1KB_Compressible() throws {
        let original = Data(repeating: 0x41, count: 1024)
        let compressed = try original.snappyCompressed()

        measure {
            _ = try! compressed.snappyDecompressed()
        }
    }

    func testDecompressBenchmark_10KB_Compressible() throws {
        let original = Data(repeating: 0x41, count: 10 * 1024)
        let compressed = try original.snappyCompressed()

        measure {
            _ = try! compressed.snappyDecompressed()
        }
    }

    func testDecompressBenchmark_100KB_Compressible() throws {
        let original = Data(repeating: 0x41, count: 100 * 1024)
        let compressed = try original.snappyCompressed()

        measure {
            _ = try! compressed.snappyDecompressed()
        }
    }

    func testDecompressBenchmark_1MB_Compressible() throws {
        let original = Data(repeating: 0x41, count: 1024 * 1024)
        let compressed = try original.snappyCompressed()

        measure {
            _ = try! compressed.snappyDecompressed()
        }
    }

    func testDecompressBenchmark_1KB_Incompressible() throws {
        var original = Data(count: 1024)
        original.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for i in 0..<1024 {
                bytes[i] = UInt8.random(in: 0...255)
            }
        }
        let compressed = try original.snappyCompressed()

        measure {
            _ = try! compressed.snappyDecompressed()
        }
    }

    func testDecompressBenchmark_10KB_Incompressible() throws {
        var original = Data(count: 10 * 1024)
        original.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for i in 0..<(10 * 1024) {
                bytes[i] = UInt8.random(in: 0...255)
            }
        }
        let compressed = try original.snappyCompressed()

        measure {
            _ = try! compressed.snappyDecompressed()
        }
    }

    // MARK: - Round-Trip Benchmarks

    func testRoundTripBenchmark_10KB() throws {
        let original = Data(repeating: 0x41, count: 10 * 1024)

        measure {
            let compressed = try! original.snappyCompressed()
            let decompressed = try! compressed.snappyDecompressed()
            precondition(decompressed == original)
        }
    }

    func testRoundTripBenchmark_100KB() throws {
        let original = Data(repeating: 0x41, count: 100 * 1024)

        measure {
            let compressed = try! original.snappyCompressed()
            let decompressed = try! compressed.snappyDecompressed()
            precondition(decompressed == original)
        }
    }

    // MARK: - Throughput Measurements

    func testCompressionThroughput() throws {
        // Measure throughput for various sizes and patterns
        print("\n=== Compression Throughput ===")

        let testCases: [(name: String, data: Data)] = [
            ("1KB Compressible", Data(repeating: 0x41, count: 1024)),
            ("10KB Compressible", Data(repeating: 0x41, count: 10 * 1024)),
            ("100KB Compressible", Data(repeating: 0x41, count: 100 * 1024)),
            ("1MB Compressible", Data(repeating: 0x41, count: 1024 * 1024)),
        ]

        for testCase in testCases {
            let start = Date()
            let iterations = testCase.data.count < 100_000 ? 1000 : 100

            for _ in 0..<iterations {
                _ = try testCase.data.snappyCompressed()
            }

            let elapsed = Date().timeIntervalSince(start)
            let totalBytes = Double(testCase.data.count * iterations)
            let throughputMBps = (totalBytes / elapsed) / (1024 * 1024)

            print("\(testCase.name): \(String(format: "%.2f", throughputMBps)) MB/s")
        }

        print("==============================\n")
    }

    func testDecompressionThroughput() throws {
        // Measure decompression throughput
        print("\n=== Decompression Throughput ===")

        let testCases: [(name: String, data: Data)] = [
            ("1KB Compressible", Data(repeating: 0x41, count: 1024)),
            ("10KB Compressible", Data(repeating: 0x41, count: 10 * 1024)),
            ("100KB Compressible", Data(repeating: 0x41, count: 100 * 1024)),
            ("1MB Compressible", Data(repeating: 0x41, count: 1024 * 1024)),
        ]

        for testCase in testCases {
            let compressed = try testCase.data.snappyCompressed()
            let start = Date()
            let iterations = testCase.data.count < 100_000 ? 1000 : 100

            for _ in 0..<iterations {
                _ = try compressed.snappyDecompressed()
            }

            let elapsed = Date().timeIntervalSince(start)
            let totalBytes = Double(testCase.data.count * iterations)
            let throughputMBps = (totalBytes / elapsed) / (1024 * 1024)

            print("\(testCase.name): \(String(format: "%.2f", throughputMBps)) MB/s")
        }

        print("================================\n")
    }

    func testCompressionRatios() throws {
        // Measure compression ratios for various patterns
        print("\n=== Compression Ratios ===")
        print("Pattern          | Original | Compressed | Ratio")
        print("-----------------|----------|------------|------")

        let testCases: [(name: String, data: Data)] = [
            ("Highly Compress", Data(repeating: 0x41, count: 10_000)),
            ("Pattern (8B)", {
                var d = Data()
                for _ in 0..<1250 {
                    d.append(contentsOf: "abcdefgh".utf8)
                }
                return d
            }()),
            ("Text (repeated)", {
                var d = Data()
                for _ in 0..<200 {
                    d.append(contentsOf: "The quick brown fox jumps over the lazy dog. ".utf8)
                }
                return d
            }()),
            ("Incompressible", {
                var d = Data(count: 10_000)
                d.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
                    for i in 0..<10_000 {
                        bytes[i] = UInt8.random(in: 0...255)
                    }
                }
                return d
            }()),
        ]

        for testCase in testCases {
            let compressed = try testCase.data.snappyCompressed()
            let ratio = Double(testCase.data.count) / Double(compressed.count)

            let name = testCase.name.padding(toLength: 16, withPad: " ", startingAt: 0)
            print("\(name) | \(String(format: "%8d", testCase.data.count)) | \(String(format: "%10d", compressed.count)) | \(String(format: "%.2f", ratio))x")
        }

        print("==========================\n")
    }
}
