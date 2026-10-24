//
//  GuidePager.swift
//  One paged walkthrough used by every guide in the app (the Xcode tutorial and
//  the re-attach guide). Swipe left/right to move between steps, or use Back/Next.
//  Keeping it in one place means the guides share the code instead of each
//  carrying its own copy.
//

import SwiftUI

struct GuideStep {
    let title: String
    let detail: String
    let symbol: String
}

struct GuidePager<Extra: View>: View {
    let steps: [GuideStep]
    let finishTitle: String
    let onFinish: () -> Void
    /// Optional extra content under a step's text (the re-attach guide puts its reset button here).
    let extra: (Int) -> Extra

    @State private var index = 0

    init(steps: [GuideStep],
         finishTitle: String,
         onFinish: @escaping () -> Void,
         @ViewBuilder extra: @escaping (Int) -> Extra) {
        self.steps = steps
        self.finishTitle = finishTitle
        self.onFinish = onFinish
        self.extra = extra
    }

    private var isLast: Bool { index == steps.count - 1 }

    var body: some View {
        VStack(spacing: 16) {
            // The page-style TabView is what makes swiping work, in both directions,
            // and it only keeps the pages next to the current one alive.
            TabView(selection: $index) {
                ForEach(steps.indices, id: \.self) { i in
                    page(for: i).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { i in
                    Circle()
                        .fill(i == index ? Color.accentColor : Color(.systemGray4))
                        .frame(width: 8, height: 8)
                }
            }

            HStack {
                Button("Back") { go(to: index - 1) }
                    .disabled(index == 0)

                Spacer()

                Button(isLast ? finishTitle : "Next") {
                    if isLast { onFinish() } else { go(to: index + 1) }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 32)
            .padding(.bottom)
        }
        .padding(.top)
    }

    private func page(for i: Int) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: steps[i].symbol)
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            Text(steps[i].title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(steps[i].detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            extra(i)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func go(to target: Int) {
        withAnimation { index = min(max(target, 0), steps.count - 1) }
    }
}

extension GuidePager where Extra == EmptyView {
    init(steps: [GuideStep], finishTitle: String, onFinish: @escaping () -> Void) {
        self.init(steps: steps, finishTitle: finishTitle, onFinish: onFinish) { _ in EmptyView() }
    }
}
