import Foundation
import SourceSortCore

// Usage: sourcesort-probe <file>...
// Prints the download source SourceSort would detect for each file.
let args = CommandLine.arguments.dropFirst()
if args.isEmpty {
    print("usage: sourcesort-probe <file>...")
    exit(1)
}
for path in args {
    let url = URL(fileURLWithPath: path)
    let s = SourceDetector.detect(at: url)
    print("""
    \(url.lastPathComponent)
      whereFroms:  \(SourceDetector.whereFroms(at: url))
      originalURL: \(s.originalURL?.absoluteString ?? "–")
      referrer:    \(s.referrerURL?.absoluteString ?? "–")
      domain:      \(s.domain ?? "–")
      domains:     \(s.domains)
      application: \(s.originatingApplication ?? "–")
    """)
}
