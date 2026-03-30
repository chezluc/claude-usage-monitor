import SwiftUI

struct MenuBarStatusView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        let percent = store.snapshot.displayPercent ?? 0
        let hasData = store.snapshot.displayPercent != nil
        let level = UsageLevel(percent: percent)
        let resetText: String? = {
            guard let plan = store.snapshot.resolvedPlans.first else { return nil }
            // Prefer resetLabel from scraper (e.g. "Resets in 3 hr 41 min") → shorten it
            if let label = plan.resetLabel, !label.isEmpty {
                // "Resets in 3 hr 41 min" → "3h41m"
                let cleaned = label
                    .replacingOccurrences(of: "Resets in ", with: "")
                    .replacingOccurrences(of: "Resets ", with: "")
                    .replacingOccurrences(of: " hr ", with: "h")
                    .replacingOccurrences(of: " min", with: "m")
                return cleaned.isEmpty ? nil : cleaned
            }
            // Fall back to ISO date countdown
            return UsageFormatters.shortCountdown(plan.resetDate)
        }()

        HStack(spacing: 5) {
            // Time remaining
            if let resetText {
                Text(resetText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(hasData ? level.color : Color.gray)
                        .frame(width: max(2, geo.size.width * CGFloat(percent) / 100))
                }
            }
            .frame(width: 60, height: 8)

            Text(hasData ? "\(percent)%" : "--%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(hasData ? level.color : Color.white.opacity(0.6))
                .monospacedDigit()
        }
        .padding(.horizontal, 4)
        .frame(maxHeight: .infinity)
    }
}

struct UsagePopoverView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            plansSection
            refreshControls
            openButton
        }
        .padding(18)
        .frame(width: 320, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.09, blue: 0.12),
                    Color(red: 0.11, green: 0.12, blue: 0.16),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude Usage")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Updated \(UsageFormatters.lastUpdatedText(store.snapshot.lastUpdated))")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.62))
            }

            Spacer(minLength: 12)

            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var plansSection: some View {
        let sections = store.snapshot.planSections

        if sections.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No usage data yet")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Open claude.ai/settings/usage in Chrome to start syncing.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        } else {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .textCase(.uppercase)
                        .tracking(0.5)

                    ForEach(section.plans) { plan in
                        PlanUsageCard(plan: plan)
                    }
                }
            }
        }

        // Last updated
        if let lastUpdated = store.snapshot.lastUpdated, !lastUpdated.isEmpty {
            Text("Last updated: \(UsageFormatters.relativeUpdatedText(lastUpdated))")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.35))
        }
    }

    private var refreshControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Refresh interval")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))

            Picker("Refresh interval", selection: $store.refreshInterval) {
                ForEach(RefreshInterval.allCases) { interval in
                    Text(interval.title).tag(interval)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var openButton: some View {
        Button {
            store.openUsagePage()
        } label: {
            HStack {
                Text("Open claude.ai/settings/usage")
                Spacer()
                Image(systemName: "arrow.up.right.square")
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.21, green: 0.46, blue: 0.98),
                        Color(red: 0.14, green: 0.72, blue: 0.88),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
    }
}

struct PlanUsageCard: View {
    let plan: UsagePlan
    @State private var animatedPercent: CGFloat = 0

    private var level: UsageLevel {
        UsageLevel(percent: plan.percent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: plan name + "X% used" right-aligned
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(plan.resetLabel ?? "Resets \(UsageFormatters.resetCountdown(plan.resetDate))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                Spacer()
                Text("\(plan.percent)% used")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(level.color)
            }

            // Progress bar — matches claude.ai style
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.08))

                    RoundedRectangle(cornerRadius: 7)
                        .fill(
                            LinearGradient(
                                colors: [
                                    level.color.opacity(0.88),
                                    level.color,
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(12, geometry.size.width * animatedPercent))
                }
            }
            .frame(height: 14)

            // Detail row — only show if we have actual message counts
            if plan.total > 0 {
                HStack {
                    Text("\(plan.used) / \(plan.total) messages")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.6))
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0.22)) {
                animatedPercent = CGFloat(plan.percent) / 100
            }
        }
        .onChange(of: plan.percent) { newPercent in
            withAnimation(.spring(duration: 0.8, bounce: 0.18)) {
                animatedPercent = CGFloat(newPercent) / 100
            }
        }
    }
}

struct BatteryIndicator: View {
    let percent: Int
    let level: UsageLevel
    let isPulsing: Bool
    @State private var pulseOpacity = 1.0

    private var clampedPercent: CGFloat {
        CGFloat(max(0, min(percent, 100))) / 100
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5)
                .stroke(Color.white.opacity(0.9), lineWidth: 1.4)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.6)
                        .fill(Color.white.opacity(0.08))

                    RoundedRectangle(cornerRadius: 1.6)
                        .fill(level.color)
                        .frame(width: max(2, (geometry.size.width - 3) * clampedPercent))
                        .opacity(pulseOpacity)
                }
                .padding(1.5)
            }

            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2.8, height: 5.2)
                    .offset(x: 3.8)
            }
        }
        .onAppear {
            updatePulse()
        }
        .onChange(of: isPulsing) { _ in
            updatePulse()
        }
    }

    private func updatePulse() {
        guard isPulsing else {
            pulseOpacity = 1
            return
        }

        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            pulseOpacity = 0.38
        }
    }
}
