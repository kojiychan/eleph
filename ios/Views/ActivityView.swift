import SwiftUI

struct ActivityView: View {
    @StateObject var viewModel: ActivityViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    dayRail
                    modePicker

                    switch viewModel.state {
                    case .idle, .loading:
                        LoadingOverlay(title: "Loading activity")
                            .frame(height: 260)
                    case .failed(let message):
                        ErrorStateView(title: "Unable to Load Activity", message: message) {
                            Task { await viewModel.load() }
                        }
                    case .loaded:
                        switch viewModel.selectedMode {
                        case .day:
                            dayView
                        case .week:
                            weekView
                        case .patterns:
                            patternsView
                        }
                    }
                }
                .padding()
            }
            .background(AppColors.groupedBackground)
            .navigationTitle("Activity")
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
        }
    }

    private var dayRail: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.moveSelectedDay(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 44)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                ForEach(viewModel.dayRailDates(), id: \.self) { date in
                    Button {
                        viewModel.selectDay(date)
                    } label: {
                        VStack(spacing: 2) {
                            Text(dayChipTopLabel(date))
                                .font(.caption2.weight(.medium))
                            Text(dayChipBottomLabel(date))
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(dayChipBackground(date), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(isSelected(date) ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                viewModel.moveSelectedDay(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private var modePicker: some View {
        Picker("Activity range", selection: $viewModel.selectedMode) {
            ForEach(ActivityDisplayMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: viewModel.selectedMode) {
            viewModel.applySelection()
        }
    }

    private var lifeCheckStrip: some View {
        HStack(spacing: 0) {
            SummaryStripItem(title: "Last activity", value: lastActivityValue, systemImage: "clock")
            Divider()
            SummaryStripItem(title: "Since last activity", value: inactivityValue, systemImage: "hourglass")
            Divider()
            SummaryStripItem(
                title: "Monitor",
                value: viewModel.deviceStatus.title.replacingOccurrences(of: "Monitor ", with: ""),
                systemImage: viewModel.deviceStatus.symbol,
                tint: viewModel.deviceStatus.tint
            )
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var dayView: some View {
        VStack(alignment: .leading, spacing: 18) {
            lifeCheckStrip

            ForEach(viewModel.groupedSessionsForSelectedDay(), id: \.section) { group in
                ActivityDaySectionView(section: group.section, sessions: group.sessions)
            }

            previousDayPeek
        }
    }

    private var weekView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    viewModel.moveSelectedDay(by: -7)
                    viewModel.selectedMode = .week
                    viewModel.applySelection()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()

                Text(weekRangeTitle)
                    .font(.headline)

                Spacer()

                Button {
                    viewModel.moveSelectedDay(by: 7)
                    viewModel.selectedMode = .week
                    viewModel.applySelection()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }

            WeekActivityMap(
                days: viewModel.weekDays(),
                selectedDate: viewModel.selectedDate,
                sessionsProvider: { viewModel.sessions(on: $0) }
            ) { date in
                viewModel.selectDay(date)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                MetricCard(title: "Most active day", value: mostActiveDayValue, systemImage: "star")
                MetricCard(title: "Longest quiet gap", value: weekLongestGapValue, systemImage: "moon")
                MetricCard(title: "Routine consistency", value: routineConsistencyValue, systemImage: "target")
            }

            weeklySessionsList
        }
    }

    private var patternsView: some View {
        let summary = viewModel.patternSummary()

        return VStack(alignment: .leading, spacing: 16) {
            lifeCheckStrip

            VStack(alignment: .leading, spacing: 4) {
                Text("Routine Patterns")
                    .font(.title2.weight(.bold))
                Text(patternsSubtitle(summary))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                PatternMetricCard(
                    title: "Avg visits / day",
                    value: averageVisitsText(summary.averageVisitsPerDay),
                    detail: "\(summary.totalSessionCount) sessions tracked",
                    systemImage: "figure.walk"
                )
                PatternMetricCard(
                    title: "Typical first activity",
                    value: timeText(forMinute: summary.typicalFirstActivityMinute),
                    detail: "Daily routine start",
                    systemImage: "sunrise"
                )
                PatternMetricCard(
                    title: "Typical last activity",
                    value: timeText(forMinute: summary.typicalLastActivityMinute),
                    detail: "Daily routine end",
                    systemImage: "moon"
                )
                PatternMetricCard(
                    title: "Avg visit length",
                    value: durationText(summary.averageSessionDuration),
                    detail: "Across visible history",
                    systemImage: "timer"
                )
            }

            routineWindows(summary)
            visitPatterns(summary)
            recentPatternSessions
        }
    }

    private func routineWindows(_ summary: ActivityPatternSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Routine Windows")
                .font(.headline)

            VStack(spacing: 0) {
                PatternRow(
                    title: "Most active part of day",
                    value: summary.mostActiveSection?.rawValue ?? "Not enough data",
                    systemImage: summary.mostActiveSection?.systemImage ?? "clock"
                )
                Divider()
                PatternRow(
                    title: "Most active day",
                    value: summary.mostActiveWeekday ?? "Not enough data",
                    systemImage: "calendar"
                )
                Divider()
                PatternRow(
                    title: "Longer activity range",
                    value: longerActivityRangeText(summary.longerActivityRange),
                    systemImage: "clock.arrow.circlepath"
                )
            }
            .padding(.horizontal, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func visitPatterns(_ summary: ActivityPatternSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Changes From Usual")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                Label(patternInsight(summary), systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline.weight(.semibold))
                Text("Patterns are based on recorded bathroom activity sessions. Labels stay cautious because Eleph tracks motion, not video or audio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var recentPatternSessions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Sessions")
                .font(.headline)

            let sessions = viewModel.recentPatternSessions()
            if sessions.isEmpty {
                EmptyStateView(title: "No Pattern Data", message: "Routine patterns will appear after activity is recorded.", systemImage: "chart.line.uptrend.xyaxis")
                    .frame(minHeight: 160)
            } else {
                VStack(spacing: 10) {
                    ForEach(sessions) { session in
                        ActivitySessionRow(session: session)
                    }
                }
            }
        }
    }

    private var previousDayPeek: some View {
        let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: viewModel.selectedDate) ?? viewModel.selectedDate
        let previousSessions = viewModel.sessions(on: previousDay)

        return VStack(spacing: 8) {
            Label("Scroll to see previous days", systemImage: "arrow.down")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                viewModel.selectDay(previousDay)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(relativeDayLabel(previousDay)), \(shortDate.string(from: previousDay))")
                            .font(.headline)
                        Text(previousSessions.isEmpty ? "No sessions recorded" : "\(previousSessions.count) sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var weeklySessionsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This Week's Sessions")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.weeklySessionCount()) sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppColors.secondaryGroupedBackground, in: Capsule())
            }

            VStack(spacing: 0) {
                ForEach(viewModel.weekDays().reversed(), id: \.self) { day in
                    Button {
                        viewModel.selectDay(day)
                    } label: {
                        HStack {
                            Text(dayListTitle(day))
                                .font(.subheadline.weight(Calendar.current.isDate(day, inSameDayAs: viewModel.selectedDate) ? .semibold : .regular))
                                .foregroundStyle(Calendar.current.isDate(day, inSameDayAs: viewModel.selectedDate) ? .blue : .primary)
                            Spacer()
                            Text("\(viewModel.sessions(on: day).count) sessions")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)

                    if day != viewModel.weekDays().first {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var lastActivityValue: String {
        viewModel.activityComparison.replacingOccurrences(of: "Last motion ", with: "")
    }

    private var inactivityValue: String {
        guard let currentInactivity = viewModel.currentInactivity else {
            return "No activity"
        }
        return Formatters.duration(currentInactivity)
    }

    private var weekLongestGapValue: String {
        guard let gap = viewModel.longestQuietGapForWeek() else {
            return "No activity"
        }
        return Formatters.duration(gap)
    }

    private var mostActiveDayValue: String {
        guard let mostActive = viewModel.mostActiveWeekday() else {
            return "No data"
        }
        return "\(shortDate.string(from: mostActive.date))"
    }

    private var routineConsistencyValue: String {
        let activeDays = viewModel.weekDays().filter { !viewModel.sessions(on: $0).isEmpty }.count
        let percentage = Int((Double(activeDays) / 7.0) * 100)
        return "\(percentage)%"
    }

    private var weekRangeTitle: String {
        let days = viewModel.weekDays()
        guard let first = days.first, let last = days.last else {
            return "This Week"
        }
        return "\(shortDate.string(from: first)) - \(shortDate.string(from: last))"
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate)
    }

    private func dayChipBackground(_ date: Date) -> Color {
        isSelected(date) ? .blue : AppColors.secondaryGroupedBackground
    }

    private func dayChipTopLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        return weekdayOnly.string(from: date)
    }

    private func dayChipBottomLabel(_ date: Date) -> String {
        dayNumber.string(from: date)
    }

    private func relativeDayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return weekdayOnly.string(from: date)
    }

    private func dayListTitle(_ date: Date) -> String {
        "\(relativeDayLabel(date)), \(shortDate.string(from: date))"
    }

    private func patternsSubtitle(_ summary: ActivityPatternSummary) -> String {
        guard summary.activeDayCount > 0 else {
            return "Patterns will appear as activity history builds."
        }
        return "Based on \(summary.activeDayCount) active days"
    }

    private func averageVisitsText(_ average: Double) -> String {
        guard average > 0 else { return "No data" }
        return String(format: "%.1f", average)
    }

    private func timeText(forMinute minute: Int?) -> String {
        guard let minute else { return "No data" }
        let hour = minute / 60
        let remainingMinute = minute % 60
        let date = Calendar.current.date(from: DateComponents(hour: hour, minute: remainingMinute)) ?? Date()
        return Formatters.time.string(from: date)
    }

    private func durationText(_ duration: TimeInterval?) -> String {
        guard let duration else { return "No data" }
        return Formatters.duration(duration)
    }

    private func longerActivityRangeText(_ range: ClosedRange<TimeInterval>?) -> String {
        guard let range else { return "No longer activity yet" }
        return "\(Formatters.duration(range.lowerBound)) - \(Formatters.duration(range.upperBound))"
    }

    private func patternInsight(_ summary: ActivityPatternSummary) -> String {
        guard summary.totalSessionCount > 0 else {
            return "No routine baseline yet"
        }
        if summary.averageVisitsPerDay < 2 {
            return "Activity is still building a routine baseline"
        }
        return "Activity is being compared with the usual routine"
    }
}

private struct PatternMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.blue)
            Text(value)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PatternRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)
                .frame(width: 24)
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 12)
    }
}

private struct SummaryStripItem: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .blue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

private struct ActivityDaySectionView: View {
    let section: ActivityDaySection
    let sessions: [ActivitySession]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(section.rawValue, systemImage: section.systemImage)
                    .font(.headline)
                Spacer()
                Text(sessionCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppColors.secondaryGroupedBackground, in: Capsule())
            }

            if sessions.isEmpty {
                Text("No activity recorded")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(sessions) { session in
                        ActivitySessionRow(session: session)
                    }
                }
            }
        }
    }

    private var sessionCountText: String {
        sessions.count == 1 ? "1 session" : "\(sessions.count) sessions"
    }
}

private struct ActivitySessionRow: View {
    let session: ActivitySession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(Formatters.time.string(from: session.startedAt)) - \(Formatters.time.string(from: session.endedAt))")
                    .font(.subheadline.weight(.semibold))
                Text(session.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(Formatters.duration(session.duration))
                    .font(.subheadline.weight(.semibold))
                Label("\(session.motionCount)", systemImage: "waveform.path.ecg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

private struct WeekActivityMap: View {
    let days: [Date]
    let selectedDate: Date
    let sessionsProvider: (Date) -> [ActivitySession]
    let selectDay: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer().frame(width: 42)
                ForEach(["Morning", "Afternoon", "Evening", "Night"], id: \.self) { title in
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            VStack(spacing: 10) {
                ForEach(days, id: \.self) { day in
                    Button {
                        selectDay(day)
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(weekdayOnly.string(from: day))
                                    .font(.caption.weight(.semibold))
                                Text(dayNumber.string(from: day))
                                    .font(.caption2)
                            }
                            .foregroundStyle(isSelected(day) ? .blue : .primary)
                            .frame(width: 34, alignment: .leading)

                            TimelineBar(sessions: sessionsProvider(day))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }
}

private struct TimelineBar: View {
    let sessions: [ActivitySession]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColors.secondaryGroupedBackground)

                ForEach(sessions) { session in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.blue.opacity(session.duration >= 20 * 60 ? 0.95 : 0.65))
                        .frame(width: blockWidth(for: session, totalWidth: proxy.size.width))
                        .offset(x: blockOffset(for: session, totalWidth: proxy.size.width))
                }
            }
        }
        .frame(height: 12)
    }

    private func blockOffset(for session: ActivitySession, totalWidth: CGFloat) -> CGFloat {
        let start = Calendar.current.dateComponents([.hour, .minute], from: session.startedAt)
        let minutes = CGFloat((start.hour ?? 0) * 60 + (start.minute ?? 0))
        return max(0, min(totalWidth - 4, totalWidth * minutes / 1_440))
    }

    private func blockWidth(for session: ActivitySession, totalWidth: CGFloat) -> CGFloat {
        max(4, min(totalWidth, totalWidth * CGFloat(session.duration / 60) / 1_440))
    }
}

private let weekdayOnly: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE"
    return formatter
}()

private let dayNumber: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "d"
    return formatter
}()

private let shortDate: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter
}()
