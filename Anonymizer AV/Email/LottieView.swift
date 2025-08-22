// LottieView.swift
import SwiftUI
import Lottie

struct LottieView: UIViewRepresentable {
    var name: String
    var loopMode: LottieLoopMode = .loop
    var speed: CGFloat = 1.0
    var play: Bool = true

    class Coordinator {
        var currentName: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView()
        view.contentMode = .scaleAspectFit
        view.loopMode = loopMode
        view.animationSpeed = speed
        view.animation = LottieAnimation.named(name)
        context.coordinator.currentName = name
        if play { view.play() }
        return view
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        if context.coordinator.currentName != name {
            uiView.animation = LottieAnimation.named(name)
            context.coordinator.currentName = name
        }
        uiView.loopMode = loopMode
        uiView.animationSpeed = speed
        if play {
            if !uiView.isAnimationPlaying { uiView.play() }
        } else {
            uiView.pause()
        }
    }
}
