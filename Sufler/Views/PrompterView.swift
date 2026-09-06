import SwiftUI
import UIKit

struct PrompterView: UIViewRepresentable {
    let text: String
    let fontSize: Double
    let spacing: Double
    let speed: Double
    let resetToken: Int
    @Binding var running: Bool

    func makeUIView(context: Context) -> ScrollingTextView {
        let view = ScrollingTextView()
        view.onPause = { running = false }
        return view
    }

    func updateUIView(_ view: ScrollingTextView, context: Context) {
        view.configure(text: text, fontSize: fontSize, spacing: spacing)
        view.speed = speed
        view.running = running
        view.onPause = { running = false }
        if view.resetToken != resetToken {
            view.resetToken = resetToken
            view.resetPosition()
        }
    }

    static func dismantleUIView(_ view: ScrollingTextView, coordinator: ()) { view.stopDisplayLink() }
}

@MainActor private final class DisplayLinkProxy: NSObject {
    weak var target: ScrollingTextView?
    @objc func step(_ link: CADisplayLink) { target?.step(link) }
}

@MainActor final class ScrollingTextView: UITextView, UITextViewDelegate {
    var speed: Double = 38
    var running = false {
        didSet { displayLink?.isPaused = !running; if !running { clock.suspend() } }
    }
    var resetToken = -1
    var onPause: (() -> Void)?
    private var clock = ScrollClock()
    private var displayLink: CADisplayLink?
    private let proxy = DisplayLinkProxy()
    private var applyingOffset = false
    private var previousText = ""
    private var previousSize = 0.0
    private var previousSpacing = 0.0

    init() {
        super.init(frame: .zero, textContainer: nil)
        delegate = self; isEditable = false; isSelectable = false
        backgroundColor = .clear; textColor = .white
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        textContainerInset = UIEdgeInsets(top: 20, left: 18, bottom: 100, right: 18)
        accessibilityLabel = "Текст суфлёра"
        proxy.target = self
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        link.isPaused = true
        displayLink = link
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bottom = max(80, bounds.height - 80)
        if abs(textContainerInset.bottom - bottom) > 1 { textContainerInset.bottom = bottom }
    }

    func configure(text: String, fontSize: Double, spacing: Double) {
        guard previousText != text || previousSize != fontSize || previousSpacing != spacing else { return }
        previousText = text; previousSize = fontSize; previousSpacing = spacing
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = spacing
        paragraph.lineBreakMode = .byWordWrapping
        let oldOffset = contentOffset.y
        attributedText = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white, .paragraphStyle: paragraph
        ])
        layoutIfNeeded()
        clock.seek(to: oldOffset, limit: limit)
        apply(clock.offset)
    }

    private var limit: Double { max(0, contentSize.height - bounds.height) }

    func step(_ link: CADisplayLink) {
        guard running, !isDragging, !isDecelerating, window != nil else { clock.suspend(); return }
        let offset = clock.tick(at: link.timestamp, speed: speed, limit: limit, running: true)
        apply(offset)
        if offset >= limit && limit > 0 { running = false; onPause?() }
    }

    private func apply(_ offset: Double) {
        applyingOffset = true
        setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        applyingOffset = false
    }

    func resetPosition() { clock.seek(to: 0, limit: limit); apply(0) }
    func stopDisplayLink() { displayLink?.invalidate(); displayLink = nil }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { running = false; onPause?() }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if !applyingOffset { clock.seek(to: scrollView.contentOffset.y, limit: limit) }
    }
}
