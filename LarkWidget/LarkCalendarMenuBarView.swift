import AppKit
import SwiftUI

struct LarkCalendarMenuBarView: View {
    @ObservedObject var store: LarkCalendarStore
    @Environment(\.openWindow) private var openWindow
    @StateObject private var navigation = ScheduleNavigation()

    private var anchorDate: Date {
        get { navigation.anchorDate }
        nonmutating set { navigation.anchorDate = newValue }
    }

    private var mode: ScheduleMode {
        get { navigation.mode }
        nonmutating set { navigation.mode = newValue }
    }

    private var modeBinding: Binding<ScheduleMode> {
        Binding(get: { mode }, set: { mode = $0 })
    }

    private var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private var weekStart: Date { calendar.dateInterval(of: .weekOfYear, for: anchorDate)?.start ?? anchorDate }
    private var displayDays: [Date] {
        if mode == .day { return [anchorDate] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }
    private var titleDate: String {
        if mode == .day { return anchorDate.formatted(.dateTime.weekday(.wide).month(.wide).day()) }
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(weekStart.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    private let timelineStartMinute = 8 * 60
    private let timelineEndMinute = 22 * 60
    private let pointsPerMinute: CGFloat = 0.48
    private let timeRulerWidth: CGFloat = 64
    private let hourLabelWidth: CGFloat = 38
    private let boardHorizontalPadding: CGFloat = 10
    private var timelineHeight: CGFloat { CGFloat(timelineEndMinute - timelineStartMinute) * pointsPerMinute }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 0) {
                header
                Divider()
                scheduleContent(now: context.date)
                Divider()
                footer
            }
        }
        .frame(width: mode == .week ? 900 : 400, height: 620)
        .background(.regularMaterial)
        .background(MenuBarWindowPositioner())
        .onAppear { refreshVisibleRange() }
        .onChange(of: mode) { _, _ in refreshVisibleRange() }
    }

    private var header: some View {
        VStack(spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Feishu Calendar").font(.headline.weight(.bold))
                    Text(titleDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer()
                Picker("View", selection: modeBinding) {
                    ForEach(ScheduleMode.allCases) { mode in Text(mode.label).tag(mode) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: mode == .week ? 150 : 120)
                Button { refreshVisibleRange() } label: {
                    Image(systemName: store.isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                }
                .buttonStyle(.borderless).disabled(store.isLoading).help("Refresh schedule")
            }
            HStack(spacing: 8) {
                Button { move(by: -1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.bordered).help(mode == .week ? "Previous week" : "Previous day")
                Button("Today") { anchorDate = .now; refreshVisibleRange() }.buttonStyle(.bordered)
                Button { move(by: 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.bordered).help(mode == .week ? "Next week" : "Next day")
                Spacer()
                if let semesterStart = store.semesterStartDate {
                    Text(SchoolWeek.number(for: anchorDate, semesterStart: semesterStart, calendar: calendar)
                        .map { "School Week \($0)" } ?? "Before semester")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                } else {
                    Button("Set school week") { openWindow(id: "settings") }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    @ViewBuilder
    private func scheduleContent(now: Date) -> some View {
        if let errorMessage = store.errorMessage {
            VStack(alignment: .leading, spacing: 10) {
                Label("Schedule unavailable", systemImage: "exclamationmark.triangle")
                    .font(.headline).foregroundStyle(.orange)
                Text(errorMessage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Button("Open Settings", systemImage: "gearshape") { openWindow(id: "settings") }.buttonStyle(.bordered)
                Spacer(minLength: 0)
            }
            .padding(22)
        } else { timelineBoard(now: now) }
    }

    private func timelineBoard(now: Date) -> some View {
        GeometryReader { geometry in
            // Every row uses the same columns, regardless of its text or events.
            let dayWidth = max(0, geometry.size.width - boardHorizontalPadding * 2 - timeRulerWidth) / CGFloat(displayDays.count)
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("TIME").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                            .padding(.leading, 3)
                            .frame(width: timeRulerWidth, alignment: .leading)
                        ForEach(displayDays, id: \.self) { day in
                            dayHeader(for: day).frame(width: dayWidth)
                        }
                    }
                    .frame(height: 44)
                    .background(.quaternary.opacity(0.45))

                    HStack(alignment: .top, spacing: 0) {
                        timeRuler
                        ForEach(displayDays, id: \.self) { day in
                            timelineDay(day, now: now)
                                .frame(width: dayWidth)
                        }
                    }
                    .frame(height: timelineHeight, alignment: .top)
                    .overlay(alignment: .trailing) { Rectangle().fill(.quaternary).frame(width: 1) }

                    if hasAllDayEvents {
                        allDayRow(dayWidth: dayWidth, now: now)
                    }
                }
                .padding(.horizontal, boardHorizontalPadding)
                .padding(.vertical, 8)
            }
        }
        .overlay(alignment: .topTrailing) {
            if store.isLoading { ProgressView().controlSize(.small).padding(.top, 10).padding(.trailing, 14) }
        }
    }

    private var hasAllDayEvents: Bool {
        displayDays.contains { !allDayEvents(on: $0).isEmpty }
    }

    @ViewBuilder
    private func allDayRow(dayWidth: CGFloat, now: Date) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("ALL DAY")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: timeRulerWidth, alignment: .leading)
                .padding(.top, 4)
            ForEach(displayDays, id: \.self) { day in
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(allDayEvents(on: day)) { event in
                        eventTile(event, now: now)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
                .frame(width: dayWidth, alignment: .topLeading)
                .frame(minHeight: 34, alignment: .topLeading)
                .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 1) }
            }
        }
        .background(.quaternary.opacity(0.25))
        .overlay(alignment: .top) { Rectangle().fill(.quaternary).frame(height: 1) }
    }

    private func allDayEvents(on day: Date) -> [CalendarEvent] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return store.events.filter { $0.isAllDay && $0.start < end && $0.end > start }
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    private func dayHeader(for day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        return VStack(spacing: 2) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.caption2.weight(.bold)).foregroundStyle(isToday ? .orange : .secondary)
            Text(day.formatted(.dateTime.day())).font(.headline.monospacedDigit())
                .foregroundStyle(isToday ? .orange : .primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isToday ? Color.orange.opacity(0.10) : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 1) }
    }

    private var timeRuler: some View {
        ZStack(alignment: .topLeading) {
            ForEach(8...22, id: \.self) { hour in
                let y = CGFloat(hour * 60 - timelineStartMinute) * pointsPerMinute
                Text(String(format: "%02d:00", hour))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .offset(y: y - 6)
            }
            ForEach(ClassBlock.all) { block in
                let y = CGFloat(block.startMinute - timelineStartMinute) * pointsPerMinute
                let height = CGFloat(block.endMinute - block.startMinute) * pointsPerMinute
                Text("\(block.number)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .frame(width: timeRulerWidth - hourLabelWidth, height: height)
                    .offset(x: hourLabelWidth, y: y)
            }
            Rectangle()
                .fill(.quaternary.opacity(0.55))
                .frame(width: 1, height: timelineHeight)
                .offset(x: hourLabelWidth)
        }
        .frame(width: timeRulerWidth, height: timelineHeight, alignment: .topLeading)
    }

    private func timelineDay(_ day: Date, now: Date) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle().fill(calendar.isDateInToday(day) ? Color.orange.opacity(0.035) : .clear)
                ForEach(8...22, id: \.self) { hour in
                    let y = CGFloat(hour * 60 - timelineStartMinute) * pointsPerMinute
                    Rectangle().fill(.quaternary.opacity(0.65)).frame(height: 1).offset(y: y)
                }
                ForEach(placements(for: day), id: \.event.id) { placement in
                    positionedEvent(placement, now: now, width: geometry.size.width)
                }
                if calendar.isDateInToday(day), let nowY = timelineY(for: now, on: day) {
                    HStack(spacing: 0) {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Rectangle().fill(.red).frame(height: 1)
                    }
                    .offset(y: nowY - 3)
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 1) }
        }
        .frame(height: timelineHeight)
    }

    private func positionedEvent(_ placement: EventPlacement, now: Date, width: CGFloat) -> some View {
        let laneGap: CGFloat = 2
        let availableWidth = max(0, width - laneGap * CGFloat(placement.laneCount - 1))
        let laneWidth = availableWidth / CGFloat(max(placement.laneCount, 1))
        let x = CGFloat(placement.lane) * (laneWidth + laneGap)
        let top = CGFloat(placement.startMinute - timelineStartMinute) * pointsPerMinute
        let height = max(CGFloat(placement.endMinute - placement.startMinute) * pointsPerMinute, 30)
        let event = placement.event
        return eventTile(event, now: now)
            .frame(width: laneWidth, height: height, alignment: .topLeading)
            .clipped()
            .offset(x: x, y: top)
            .zIndex(Double(placement.lane + 1))
    }

    private func eventTile(_ event: CalendarEvent, now: Date) -> some View {
        let color = eventColor(event)
        let state = event.state(at: now)
        return HStack(alignment: .top, spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(state == .passed ? .secondary : .primary)
                HStack(spacing: 3) {
                    Text(event.start.formatted(date: .omitted, time: .shortened))
                        .fixedSize(horizontal: true, vertical: false)
                    if let location = event.location {
                        Text("· \(location)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 8, weight: .medium, design: .monospaced))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .background(color.opacity(state == .passed ? 0.06 : 0.12), in: RoundedRectangle(cornerRadius: 5))
        .opacity(state == .passed ? 0.72 : 1)
        .help("\(event.title) · \(event.start.formatted(date: .omitted, time: .shortened))–\(event.end.formatted(date: .omitted, time: .shortened))\(event.location.map { " · \($0)" } ?? "")")
    }

    private func placements(for day: Date) -> [EventPlacement] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
              let visibleStart = calendar.date(byAdding: .minute, value: timelineStartMinute, to: dayStart),
              let visibleEnd = calendar.date(byAdding: .minute, value: timelineEndMinute, to: dayStart) else { return [] }
        let relevant = store.events.filter { !$0.isAllDay && $0.start < min(dayEnd, visibleEnd) && $0.end > max(dayStart, visibleStart) }
        let sorted = relevant.map { event in
            EventPlacement(event: event,
                           startMinute: event.start <= visibleStart ? timelineStartMinute : minuteOfDay(event.start),
                           endMinute: event.end >= visibleEnd ? timelineEndMinute : minuteOfDay(event.end),
                           lane: 0,
                           laneCount: 1,
                           cluster: 0)
        }.sorted {
            if $0.startMinute != $1.startMinute { return $0.startMinute < $1.startMinute }
            if $0.endMinute != $1.endMinute { return $0.endMinute > $1.endMinute }
            return $0.event.id < $1.event.id
        }
        var lanes: [[EventPlacement]] = []
        var output: [EventPlacement] = []
        var cluster = 0
        var clusterEnd = Int.min
        var clusterStartIndex = 0
        for event in sorted {
            if event.startMinute >= clusterEnd {
                if !output.isEmpty {
                    let clusterLaneCount = lanes.count
                    for index in clusterStartIndex..<output.count {
                        output[index].laneCount = clusterLaneCount
                    }
                    clusterStartIndex = output.count
                    cluster += 1
                }
                lanes.removeAll(keepingCapacity: true)
                clusterEnd = event.endMinute
            } else {
                clusterEnd = max(clusterEnd, event.endMinute)
            }
            let lane = lanes.firstIndex(where: { lane in lane.last.map { $0.endMinute <= event.startMinute } ?? true }) ?? lanes.count
            if lane == lanes.count { lanes.append([]) }
            var placed = event
            placed.lane = lane
            placed.cluster = cluster
            lanes[lane].append(placed)
            output.append(placed)
        }
        if !output.isEmpty {
            let clusterLaneCount = lanes.count
            for index in clusterStartIndex..<output.count {
                output[index].laneCount = clusterLaneCount
            }
        }
        return output
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private func timelineY(for date: Date, on day: Date) -> CGFloat? {
        guard calendar.isDate(date, inSameDayAs: day) else { return nil }
        let minute = minuteOfDay(date)
        guard minute >= timelineStartMinute, minute <= timelineEndMinute else { return nil }
        return CGFloat(minute - timelineStartMinute) * pointsPerMinute
    }

    private func eventColor(_ event: CalendarEvent) -> Color {
        guard let eventColor = event.color, eventColor != 0, eventColor != -1 else {
            guard let calendarColor = store.selectedCalendarColor, calendarColor != 0, calendarColor != -1 else {
                return .accentColor
            }
            return rgbColor(calendarColor)
        }
        return rgbColor(eventColor)
    }

    private func rgbColor(_ value: Int) -> Color {
        let rgb = UInt32(truncatingIfNeeded: value)
        return Color(
            red: Double((rgb >> 16) & 0xff) / 255,
            green: Double((rgb >> 8) & 0xff) / 255,
            blue: Double(rgb & 0xff) / 255
        )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(store.isConfigured ? (store.isLoading ? "Updating calendar…" : "Synced with Feishu") : "Connect Feishu to view your calendar")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Button { openWindow(id: "settings") } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).help("Open Settings")
            Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(.borderless).help("Quit Feishu Calendar")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func move(by amount: Int) {
        let unit: Calendar.Component = mode == .week ? .weekOfYear : .day
        if let nextDate = calendar.date(byAdding: unit, value: amount, to: anchorDate) {
            anchorDate = nextDate
            refreshVisibleRange()
        }
    }

    private func refreshVisibleRange() {
        store.refresh(for: mode == .week ? weekStart : anchorDate)
    }
}

private enum ScheduleMode: String, CaseIterable, Identifiable {
    case week, day
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

@MainActor
private final class ScheduleNavigation: ObservableObject {
    @Published var anchorDate = Date.now
    @Published var mode: ScheduleMode = .week
}

private struct ClassBlock: Identifiable {
    let number: Int
    let startMinute: Int
    let endMinute: Int
    var id: Int { number }

    static let all: [ClassBlock] = [
        .init(number: 1, startMinute: 8 * 60 + 30, endMinute: 9 * 60 + 15),
        .init(number: 2, startMinute: 9 * 60 + 20, endMinute: 10 * 60 + 5),
        .init(number: 3, startMinute: 10 * 60 + 25, endMinute: 11 * 60 + 10),
        .init(number: 4, startMinute: 11 * 60 + 15, endMinute: 12 * 60),
        .init(number: 5, startMinute: 13 * 60 + 30, endMinute: 14 * 60 + 15),
        .init(number: 6, startMinute: 14 * 60 + 20, endMinute: 15 * 60 + 5),
        .init(number: 7, startMinute: 15 * 60 + 25, endMinute: 16 * 60 + 10),
        .init(number: 8, startMinute: 16 * 60 + 15, endMinute: 17 * 60),
        .init(number: 9, startMinute: 17 * 60 + 5, endMinute: 17 * 60 + 50),
        .init(number: 10, startMinute: 18 * 60 + 30, endMinute: 19 * 60 + 15),
        .init(number: 11, startMinute: 19 * 60 + 20, endMinute: 20 * 60 + 5),
        .init(number: 12, startMinute: 20 * 60 + 15, endMinute: 21 * 60),
        .init(number: 13, startMinute: 21 * 60 + 5, endMinute: 21 * 60 + 50)
    ]
}

private struct EventPlacement {
    let event: CalendarEvent
    let startMinute: Int
    let endMinute: Int
    var lane: Int
    var laneCount: Int
    var cluster: Int
}
