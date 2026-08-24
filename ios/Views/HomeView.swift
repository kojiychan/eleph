import SwiftUI

struct HomeView: View {
    @StateObject var viewModel: HomeViewModel
    let viewAllActivity: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    switch viewModel.state {
                    case .idle, .loading:
                        LoadingOverlay(title: "Loading home")
                            .frame(height: 360)
                    case .failed(let message):
                        ErrorStateView(title: "Unable to Load Home", message: message) {
                            Task { await viewModel.load() }
                        }
                    case .loaded(let snapshot):
                        homeContent(snapshot)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(AppColors.groupedBackground)
            .navigationTitle("Home")
            .homeToolbar()
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
        }
    }

    private func homeContent(_ snapshot: AppSnapshot) -> some View {
        let summary = snapshot.summaries.first
        let currentInactivity = summary?.currentInactivity ?? viewModel.inactivitySinceLastMotion(snapshot.device)
        let isOffline = snapshot.device.connectionStatus == .offline

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting(name: snapshot.profile.caregiverName))
                    .font(.largeTitle.weight(.bold))
                Text(snapshot.device.displayName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)

            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.plainStatus(for: snapshot))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isOffline ? .orange : .primary)
                Spacer()
                if viewModel.isUsingMockData {
                    Label("Demo data", systemImage: "wand.and.stars")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppColors.secondaryGroupedBackground, in: Capsule())
                }
            }

            if let lastUpdatedAt = viewModel.lastUpdatedAt {
                Text("Last updated \(Formatters.relative(lastUpdatedAt))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            DeviceConnectionBanner(device: snapshot.device)

            StatusCard(
                state: viewModel.wellnessState(for: snapshot),
                lastMotionAt: snapshot.device.lastMotionAt,
                isDataStale: isOffline
            )

            InactivityProgressBar(
                currentInactivity: currentInactivity,
                cautionThresholdHours: snapshot.alertPreferences.cautionThresholdHours,
                criticalThresholdHours: snapshot.alertPreferences.criticalThresholdHours
            )

            dailySummary(summary, device: snapshot.device)

            recentSessions(snapshot.motionEvents)
        }
    }

    private func dailySummary(_ summary: DailyActivitySummary?, device: MonitorDevice) -> some View {
        let status: BathroomMotionState = device.connectionStatus == .offline ? .monitorOffline : (summary?.currentBathroomState ?? .empty)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.title2.weight(.bold))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricCard(title: "Bathroom visits", value: "\(summary?.visits ?? 0)", systemImage: "figure.walk")
                MetricCard(title: "Current inactivity", value: Formatters.duration(summary?.currentInactivity ?? 0), systemImage: "timer")
                MetricCard(title: "Longest inactivity", value: Formatters.duration(summary?.longestInactivity ?? 0), systemImage: "moon.zzz")
                MetricCard(title: "Bathroom status", value: status.rawValue, systemImage: "sensor.tag.radiowaves.forward", tint: device.connectionStatus.tint)
            }
        }
    }

    private func recentSessions(_ events: [MotionEvent]) -> some View {
        let groups = recentSessionGroups(from: events)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Sessions")
                    .font(.title2.weight(.bold))
                Spacer()
                Button("View Activity", action: viewAllActivity)
            }

            if groups.isEmpty {
                EmptyStateView(title: "No motion recorded yet today", message: "Activity updates will appear here when the monitor detects motion.", systemImage: "clock.badge.questionmark")
                    .frame(minHeight: 170)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(groups, id: \.section) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(group.section.rawValue, systemImage: group.section.systemImage)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(group.sessions.count == 1 ? "1 session" : "\(group.sessions.count) sessions")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(AppColors.secondaryGroupedBackground, in: Capsule())
                            }

                            VStack(spacing: 0) {
                                ForEach(group.sessions) { session in
                                    HomeSessionRow(session: session)
                                    if session.id != group.sessions.last?.id {
                                        Divider()
                                            .padding(.leading, 44)
                                    }
                                }
                            }
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private func recentSessionGroups(from events: [MotionEvent]) -> [(section: ActivityDaySection, sessions: [ActivitySession])] {
        let todayEvents = events
            .filter { Calendar.current.isDateInToday($0.detectedAt) }
            .sorted { $0.detectedAt < $1.detectedAt }
        let sessions = groupedSessions(from: todayEvents)

        return ActivityDaySection.allCases
            .compactMap { section -> (section: ActivityDaySection, sessions: [ActivitySession])? in
                let sectionSessions = sessions
                    .filter { section.contains($0.startedAt) }
                    .sorted { $0.startedAt > $1.startedAt }
                guard !sectionSessions.isEmpty else { return nil }
                return (section, Array(sectionSessions.prefix(2)))
            }
            .sorted {
                ($0.sessions.first?.startedAt ?? .distantPast) > ($1.sessions.first?.startedAt ?? .distantPast)
            }
            .prefix(2)
            .map { ($0.section, $0.sessions) }
    }

    private func groupedSessions(from events: [MotionEvent]) -> [ActivitySession] {
        guard var currentStart = events.first?.detectedAt else {
            return []
        }

        let sessionGap: TimeInterval = 5 * 60
        var currentEnd = currentStart
        var motionCount = 0
        var sessions: [ActivitySession] = []

        for event in events {
            if event.detectedAt.timeIntervalSince(currentEnd) > sessionGap {
                sessions.append(ActivitySession(startedAt: currentStart, endedAt: currentEnd, motionCount: motionCount))
                currentStart = event.detectedAt
                motionCount = 0
            }

            currentEnd = event.detectedAt
            motionCount += 1
        }

        sessions.append(ActivitySession(startedAt: currentStart, endedAt: currentEnd, motionCount: motionCount))
        return sessions
    }

    private func greeting(name: String) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let prefix: String
        switch hour {
        case 5..<12: prefix = "Good Morning"
        case 12..<17: prefix = "Good Afternoon"
        default: prefix = "Good Evening"
        }
        return "\(prefix), \(name)"
    }
}

private struct HomeSessionRow: View {
    let session: ActivitySession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(Formatters.time.string(from: session.startedAt)) - \(Formatters.time.string(from: session.endedAt))")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(session.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(Formatters.duration(session.duration))
                .font(.subheadline.weight(.semibold))

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
    }

    private var iconName: String {
        switch session.label {
        case "Longer activity":
            return "clock.arrow.circlepath"
        case "Quick visit":
            return "figure.walk"
        default:
            return "circle.dotted"
        }
    }
}

private extension View {
    @ViewBuilder
    func homeToolbar() -> some View {
        #if os(iOS)
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                } label: {
                    Image(systemName: "bell")
                }
                .accessibilityLabel("Notifications")
            }
        }
        #else
        toolbar {
            Button {
            } label: {
                Image(systemName: "bell")
            }
            .accessibilityLabel("Notifications")
        }
        #endif
    }
}

#Preview("Normal") {
    MainTabPreview(scenario: .normalOnline)
}

#Preview("Offline") {
    MainTabPreview(scenario: .offlineSeveralHours)
}
