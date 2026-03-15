import WebKit

/// Serves local files via the marker-file:// URL scheme.
/// Usage: marker-file:///absolute/path/to/file.png
class MarkerSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme == "marker-file" else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        // marker-file:///path/to/file → /path/to/file
        let filePath = url.path

        guard FileManager.default.fileExists(atPath: filePath) else {
            // Return 1x1 transparent PNG placeholder for missing images
            let placeholder = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
            let response = URLResponse(url: url, mimeType: "image/png", expectedContentLength: placeholder.count, textEncodingName: nil)
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(placeholder)
            urlSchemeTask.didFinish()
            return
        }

        guard let data = FileManager.default.contents(atPath: filePath) else {
            urlSchemeTask.didFailWithError(URLError(.cannotOpenFile))
            return
        }

        let mimeType = Self.mimeType(for: filePath)
        let response = URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: nil)
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Nothing to cancel — file reads are synchronous
    }

    private static func mimeType(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "ico": return "image/x-icon"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}
