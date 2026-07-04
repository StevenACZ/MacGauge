import AppKit

extension NSStatusBarButton {
    /// Quick squash-and-pop scale used by every status item on click.
    func bounce() {
        wantsLayer = true
        guard let layer else { return }
        let bounds = layer.bounds
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: bounds.midX, y: bounds.midY)

        let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
        bounce.values = [1.0, 0.86, 1.08, 1.0]
        bounce.keyTimes = [0, 0.35, 0.7, 1]
        bounce.duration = 0.28
        bounce.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(bounce, forKey: "bounce")
    }
}
