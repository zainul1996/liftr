import Foundation
import LIFTRCore

/// Reads only the top-level metadata object using a fixed-size buffer.
/// Canonical JSON may place metadata before or after a large samples array.
enum RecordingMetadataReader {
  static func read(from url: URL) throws -> RecordingMetadata {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let key = Array("metadata".utf8)
    var depth = 0
    var inString = false
    var escaped = false
    var candidate: [UInt8] = []
    var readingTopLevelString = false
    var metadataFound = false
    var collecting = false
    var metadataDepth = 0
    var metadata = Data()
    while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
      for byte in chunk {
        if metadataFound {
          if !collecting {
            if byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 || byte == 0x3A {
              continue
            }
            guard byte == 0x7B else { throw ReaderError.invalidMetadata }
            collecting = true
            metadataDepth = 1
            metadata.append(byte)
            inString = false
            escaped = false
            continue
          }
          metadata.append(byte)
          guard metadata.count <= 262_144 else { throw ReaderError.metadataTooLarge }
          if inString {
            if escaped {
              escaped = false
            } else if byte == 0x5C {
              escaped = true
            } else if byte == 0x22 {
              inString = false
            }
          } else {
            if byte == 0x22 {
              inString = true
            } else if byte == 0x7B || byte == 0x5B {
              metadataDepth += 1
            } else if byte == 0x7D || byte == 0x5D {
              metadataDepth -= 1
              if metadataDepth == 0 {
                return try RecordingJSON.decoder().decode(RecordingMetadata.self, from: metadata)
              }
            }
          }
        } else if inString {
          if escaped {
            escaped = false
            if readingTopLevelString { candidate.append(byte) }
          } else if byte == 0x5C {
            escaped = true
            if readingTopLevelString { candidate.append(byte) }
          } else if byte == 0x22 {
            inString = false
            if readingTopLevelString && candidate == key { metadataFound = true }
            readingTopLevelString = false
          } else if readingTopLevelString && candidate.count <= key.count {
            candidate.append(byte)
          }
        } else {
          if byte == 0x22 {
            inString = true
            readingTopLevelString = depth == 1
            candidate = []
          } else if byte == 0x7B || byte == 0x5B {
            depth += 1
          } else if byte == 0x7D || byte == 0x5D {
            depth -= 1
          }
        }
      }
    }
    throw ReaderError.missingMetadata
  }
  enum ReaderError: Error { case missingMetadata, invalidMetadata, metadataTooLarge }
}
