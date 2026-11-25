import SwiftUI
import WebKit

public struct VideoEmbedView: View {
    let urlString: String
    let platform: String

    @State private var isLoading: Bool = true
    @State private var hasError: Bool = false

    public init(urlString: String, platform: String) {
        self.urlString = urlString
        self.platform = platform
    }

    private var embedURL: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. TikTok Embed
        if trimmed.contains("tiktok.com") {
            // Regex für Video-ID
            if let regex = try? NSRegularExpression(pattern: #"(?<=/video/)\d+"#),
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let range = Range(match.range, in: trimmed) {
                let videoID = String(trimmed[range])
                return URL(string: "https://www.tiktok.com/embed/v2/\(videoID)")
            }
        }

        // 2. Facebook / fb.watch Embed
        if trimmed.contains("facebook.com") || trimmed.contains("fb.watch") {
            if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                return URL(string: "https://www.facebook.com/plugins/video.php?href=\(encoded)&show_text=false")
            }
        }

        // 3. YouTube Shorts / Watch Embed
        if trimmed.contains("youtube.com") || trimmed.contains("youtu.be") {
            if trimmed.contains("shorts/") {
                let components = trimmed.components(separatedBy: "shorts/")
                if let idPart = components.last?.split(separator: "?").first {
                    return URL(string: "https://www.youtube-nocookie.com/embed/\(idPart)?playsinline=1")
                }
            } else if trimmed.contains("watch?v=") {
                let components = trimmed.components(separatedBy: "watch?v=")
                if let idPart = components.last?.split(separator: "&").first {
                    return URL(string: "https://www.youtube-nocookie.com/embed/\(idPart)?playsinline=1")
                }
            } else if trimmed.contains("youtu.be/") {
                let components = trimmed.components(separatedBy: "youtu.be/")
                if let idPart = components.last?.split(separator: "?").first {
                    return URL(string: "https://www.youtube-nocookie.com/embed/\(idPart)?playsinline=1")
                }
            }
        }

        return URL(string: trimmed)
    }

    public var body: some View {
        ZStack {
            Color.black

            if let targetURL = embedURL {
                WebViewRepresentable(url: targetURL, isLoading: $isLoading, hasError: $hasError)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Video-Vorschau nicht verfügbar")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if isLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            }

            // Fallback / Externer Link Button oben rechts oder bei Fehler
            VStack {
                HStack {
                    Spacer()
                    if let directURL = URL(string: urlString) {
                        Link(destination: directURL) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right.square")
                                Text("Original")
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .foregroundColor(.white)
                        }
                        .padding(12)
                    }
                }
                Spacer()

                if hasError {
                    VStack(spacing: 8) {
                        Text("Einbettung eingeschränkt.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        if let directURL = URL(string: urlString) {
                            Link(destination: directURL) {
                                Text("Originalvideo extern öffnen")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }
}

private struct WebViewRepresentable: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var hasError: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false

        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewRepresentable

        init(_ parent: WebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
                self.parent.hasError = false
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.hasError = true
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.hasError = true
            }
        }
    }
}
