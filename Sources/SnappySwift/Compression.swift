/// Snappy compression implementation
///
/// This file implements the core compression algorithm based on Google's C++ implementation.

import Foundation

// MARK: - Compression

extension Snappy {

    /// Compress data using the Snappy algorithm.
    ///
    /// - Parameters:
    ///   - input: Buffer containing uncompressed data
    ///   - output: Buffer to write compressed data to
    ///   - options: Compression options
    /// - Returns: Number of bytes written to output buffer
    /// - Throws: `SnappyError` if compression fails
    static func compressImpl(
        _ input: UnsafeBufferPointer<UInt8>,
        to output: UnsafeMutableBufferPointer<UInt8>,
        options: CompressionOptions
    ) throws -> Int {
        // Validate input size
        guard input.count <= Int(UInt32.max) else {
            throw SnappyError.inputTooLarge
        }

        // Verify output buffer is large enough
        let maxCompressed = maxCompressedLength(input.count)
        guard output.count >= maxCompressed else {
            throw SnappyError.insufficientBuffer
        }

        // Write uncompressed length as varint
        var op = 0  // Output position
        op += Varint.encode32(UInt32(input.count), to: output, at: op)

        // Handle empty input
        guard input.count > 0 else {
            return op
        }

        // Compress in fragments of at most 64 KiB to avoid UInt16 overflow in hash table
        // This matches the C++ reference implementation's block size
        let maxFragmentSize = 65536  // 64 KiB
        var inputOffset = 0

        while inputOffset < input.count {
            let fragmentSize = min(maxFragmentSize, input.count - inputOffset)
            let fragmentEnd = inputOffset + fragmentSize

            // Create fragment view
            let fragment = UnsafeBufferPointer(rebasing: input[inputOffset..<fragmentEnd])

            // Compress this fragment
            let bytesWritten = try compressFragment(
                fragment,
                to: output,
                outputOffset: op,
                options: options
            )

            op += bytesWritten
            inputOffset = fragmentEnd
        }

        return op
    }

    /// Compress a single fragment of data.
    ///
    /// This is the main compression loop implementing the LZ77-based algorithm.
    ///
    /// - Parameters:
    ///   - input: Buffer containing uncompressed data
    ///   - output: Buffer to write compressed operations to
    ///   - outputOffset: Starting offset in output buffer
    ///   - options: Compression options
    /// - Returns: Number of bytes written to output buffer
    private static func compressFragment(
        _ input: UnsafeBufferPointer<UInt8>,
        to output: UnsafeMutableBufferPointer<UInt8>,
        outputOffset: Int,
        options: CompressionOptions
    ) throws -> Int {
        let inputSize = input.count

        // For very small inputs, just emit as literal
        if inputSize < SnappyConstants.minMatchLength {
            return emitLiteral(
                input,
                to: output,
                at: outputOffset
            )
        }

        // Create hash table
        let tableSize = computeHashTableSize(inputSize)
        var hashTable = [UInt16](repeating: 0, count: tableSize)
        let hashMask = computeHashMask(tableSize)

        var ip = 0              // Input position
        var nextEmit = 0        // Next byte to emit as literal
        var op = outputOffset   // Output position
        var nextIp = 1          // Next position to check
        var skip = 32           // Skip increment for incompressible data

        // Leave enough room at end for final literal
        let inputLimit = inputSize - 15

        // Main compression loop
        while ip < inputLimit {
            // Track where we started looking for this match
            var candidateOffset = 0
            var bytes: UInt32 = 0

            // Skip heuristic: try increasingly large steps if no matches found
            repeat {
                ip = nextIp
                let bytesSkipped = ip - nextEmit

                // Calculate skip increment (divide by 32)
                skip = bytesSkipped >> 5
                nextIp = ip + 1 + skip

                // Exit if we've reached the limit
                if nextIp > inputLimit {
                    break
                }

                // Load 4 bytes for hashing
                bytes = load32(from: input, at: ip)
                let hash = hashBytes(bytes, mask: hashMask)

                // Look up candidate match
                candidateOffset = Int(hashTable[hash])

                // Store current position in hash table
                hashTable[hash] = UInt16(truncatingIfNeeded: ip)

                // Check if we have a valid candidate with matching bytes
            } while candidateOffset == 0 ||
                    ip - candidateOffset > 65535 ||
                    load32(from: input, at: candidateOffset) != bytes

            // Exit if skip heuristic went past limit
            if nextIp > inputLimit {
                break
            }

            // Found a match!

            // Emit literal for unmatched bytes [nextEmit, ip)
            if nextEmit < ip {
                op += emitLiteral(
                    UnsafeBufferPointer(rebasing: input[nextEmit..<ip]),
                    to: output,
                    at: op
                )
            }

            // Find full match length
            let matchLength = findMatchLength(
                in: input,
                s1: candidateOffset + 4,
                s2: ip + 4,
                limit: inputSize
            ) + 4

            // Emit copy operation
            op += emitCopy(
                offset: ip - candidateOffset,
                length: matchLength,
                to: output,
                at: op
            )

            // Skip matched bytes and update hash table
            ip += matchLength
            nextEmit = ip

            // Reset skip counter after finding a match
            skip = 32
            nextIp = ip + 1

            // Insert intermediate positions into hash table
            // This helps find matches within the matched region
            if ip < inputLimit {
                let nextBytes = load32(from: input, at: ip - 1)
                let nextHash = hashBytes(nextBytes, mask: hashMask)
                hashTable[nextHash] = UInt16(truncatingIfNeeded: ip - 1)
            }
        }

        // Emit final literal for remaining bytes
        if nextEmit < inputSize {
            op += emitLiteral(
                UnsafeBufferPointer(rebasing: input[nextEmit..<inputSize]),
                to: output,
                at: op
            )
        }

        return op - outputOffset
    }

    // MARK: - Helper Functions

    /// Compute hash table size based on input size
    private static func computeHashTableSize(_ inputSize: Int) -> Int {
        var size = min(inputSize, SnappyConstants.maxHashTableSize)
        size = max(size, SnappyConstants.minHashTableSize)

        // Round up to next power of 2
        var bits = 0
        var temp = size - 1
        while temp > 0 {
            bits += 1
            temp >>= 1
        }

        return 1 << bits
    }

    /// Compute hash mask for table lookup
    private static func computeHashMask(_ tableSize: Int) -> Int {
        // For power-of-2 table size, mask is tableSize - 1
        return tableSize - 1
    }

    /// Hash 4 bytes using software fallback
    @inline(__always)
    private static func hashBytes(_ bytes: UInt32, mask: Int) -> Int {
        let hash = SnappyConstants.hashMagic &* bytes
        return Int(hash >> (31 - SnappyConstants.maxHashTableBits)) & mask
    }

    /// Load 4 bytes as little-endian UInt32
    @inline(__always)
    private static func load32(from buffer: UnsafeBufferPointer<UInt8>, at offset: Int) -> UInt32 {
        precondition(offset + 4 <= buffer.count, "Buffer overflow")

        // Use unaligned load to avoid alignment requirements
        let b0 = UInt32(buffer[offset])
        let b1 = UInt32(buffer[offset + 1])
        let b2 = UInt32(buffer[offset + 2])
        let b3 = UInt32(buffer[offset + 3])

        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    /// Find length of matching bytes between two positions
    @inline(__always)
    private static func findMatchLength(
        in buffer: UnsafeBufferPointer<UInt8>,
        s1: Int,
        s2: Int,
        limit: Int
    ) -> Int {
        var matched = 0
        var pos1 = s1
        var pos2 = s2

        // Compare 8 bytes at a time when possible
        while pos2 + 8 <= limit && pos1 + 8 <= limit {
            let b1 = load64(from: buffer, at: pos1)
            let b2 = load64(from: buffer, at: pos2)

            if b1 != b2 {
                break
            }

            matched += 8
            pos1 += 8
            pos2 += 8
        }

        // Compare 4 bytes at a time
        if pos2 + 4 <= limit && pos1 + 4 <= limit {
            let b1 = load32(from: buffer, at: pos1)
            let b2 = load32(from: buffer, at: pos2)

            if b1 == b2 {
                matched += 4
                pos1 += 4
                pos2 += 4
            }
        }

        // Compare remaining bytes
        while pos2 < limit && pos1 < limit && buffer[pos1] == buffer[pos2] {
            matched += 1
            pos1 += 1
            pos2 += 1
        }

        return matched
    }

    /// Load 8 bytes as little-endian UInt64
    @inline(__always)
    private static func load64(from buffer: UnsafeBufferPointer<UInt8>, at offset: Int) -> UInt64 {
        precondition(offset + 8 <= buffer.count, "Buffer overflow")

        // Use unaligned load to avoid alignment requirements
        let b0 = UInt64(buffer[offset])
        let b1 = UInt64(buffer[offset + 1])
        let b2 = UInt64(buffer[offset + 2])
        let b3 = UInt64(buffer[offset + 3])
        let b4 = UInt64(buffer[offset + 4])
        let b5 = UInt64(buffer[offset + 5])
        let b6 = UInt64(buffer[offset + 6])
        let b7 = UInt64(buffer[offset + 7])

        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24) |
               (b4 << 32) | (b5 << 40) | (b6 << 48) | (b7 << 56)
    }

    /// Emit a literal operation
    ///
    /// - Parameters:
    ///   - literal: Bytes to emit as literal
    ///   - output: Output buffer
    ///   - at: Output position
    /// - Returns: Number of bytes written
    private static func emitLiteral(
        _ literal: UnsafeBufferPointer<UInt8>,
        to output: UnsafeMutableBufferPointer<UInt8>,
        at offset: Int
    ) -> Int {
        let length = literal.count
        precondition(length > 0, "Literal length must be > 0")
        precondition(offset + 1 + 4 + length <= output.count, "Output buffer overflow")

        var op = offset
        let (tag, extraBytes) = Tag.encodeLiteral(length: length)

        // Write tag
        output[op] = tag
        op += 1

        // Write extra bytes if needed
        if extraBytes > 0 {
            var lengthValue = UInt32(length - 1)
            for _ in 0..<extraBytes {
                output[op] = UInt8(truncatingIfNeeded: lengthValue)
                lengthValue >>= 8
                op += 1
            }
        }

        // Copy literal data (safe for already-initialized memory)
        output.baseAddress!.advanced(by: op).update(
            from: literal.baseAddress!,
            count: length
        )
        op += length

        return op - offset
    }

    /// Emit a copy operation
    ///
    /// - Parameters:
    ///   - offset: Offset to copy from (distance back)
    ///   - length: Number of bytes to copy
    ///   - output: Output buffer
    ///   - at: Output position
    /// - Returns: Number of bytes written
    private static func emitCopy(
        offset: Int,
        length: Int,
        to output: UnsafeMutableBufferPointer<UInt8>,
        at outOffset: Int
    ) -> Int {
        precondition(offset > 0, "Offset must be > 0")
        precondition(length >= 4, "Copy length must be >= 4")

        var op = outOffset
        var remainingLength = length

        // Try to use copy-1 encoding (1-byte offset) if possible
        if remainingLength >= 4 && remainingLength <= 11 && offset < 2048 {
            let (tag, offsetByte) = Tag.encodeCopy1Byte(
                offset: offset,
                length: remainingLength
            )
            output[op] = tag
            output[op + 1] = offsetByte
            op += 2
            remainingLength = 0
        }

        // Emit longer copies in 64-byte chunks using copy-2
        while remainingLength >= 64 {
            let tag = Tag.encodeCopy2Byte(offset: offset, length: 64)
            output[op] = tag

            // Write 2-byte little-endian offset
            let offset16 = UInt16(truncatingIfNeeded: offset)
            output[op + 1] = UInt8(truncatingIfNeeded: offset16)
            output[op + 2] = UInt8(truncatingIfNeeded: offset16 >> 8)

            op += 3
            remainingLength -= 64
        }

        // Emit remaining bytes
        if remainingLength > 0 {
            if offset < 65536 {
                // Use copy-2 (2-byte offset)
                let tag = Tag.encodeCopy2Byte(offset: offset, length: remainingLength)
                output[op] = tag

                let offset16 = UInt16(truncatingIfNeeded: offset)
                output[op + 1] = UInt8(truncatingIfNeeded: offset16)
                output[op + 2] = UInt8(truncatingIfNeeded: offset16 >> 8)

                op += 3
            } else {
                // Use copy-4 (4-byte offset)
                let tag = Tag.encodeCopy4Byte(offset: offset, length: remainingLength)
                output[op] = tag

                let offset32 = UInt32(truncatingIfNeeded: offset)
                output[op + 1] = UInt8(truncatingIfNeeded: offset32)
                output[op + 2] = UInt8(truncatingIfNeeded: offset32 >> 8)
                output[op + 3] = UInt8(truncatingIfNeeded: offset32 >> 16)
                output[op + 4] = UInt8(truncatingIfNeeded: offset32 >> 24)

                op += 5
            }
        }

        return op - outOffset
    }
}
