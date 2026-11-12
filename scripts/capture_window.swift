// Prints the CGWindowID of the first on-screen window owned by an app. Usage: swift capture_window.swift Glide
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "Glide"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerName as String] as? String) == owner && (w[kCGWindowLayer as String] as? Int) == 0 {
    print(w[kCGWindowNumber as String] as! Int)
    exit(0)
}
exit(1)
