import SwiftUI
import CoreKit

private enum GoalsMapMetrics {
    static let gap: CGFloat = 8
    static let minNodeWidth: CGFloat = 72
    static let layerSpacing: CGFloat = 28
    static let minScale: CGFloat = 0.6
    static let maxScale: CGFloat = 2.0
    static let spaceName = "goalsMapCanvas"
}

/// Node frames in the canvas coordinate space, collected for edge drawing.
private nonisolated struct GoalsMapFrameKey: PreferenceKey {
    nonisolated static var defaultValue: [UUID: CGRect] { [:] }
    nonisolated static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// All edges as elbow lines (parent bottom-centre to child top-centre).
private nonisolated struct GoalsMapEdges: Shape {
    let frames: [UUID: CGRect]
    let edges: [MapLayout.Edge]

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        for edge in edges {
            guard let from = frames[edge.from], let to = frames[edge.to] else { continue }
            let start = CGPoint(x: from.midX, y: from.maxY)
            let end = CGPoint(x: to.midX, y: to.minY)
            let midY = (start.y + end.y) / 2
            path.move(to: start)
            path.addLine(to: CGPoint(x: start.x, y: midY))
            path.addLine(to: CGPoint(x: end.x, y: midY))
            path.addLine(to: end)
        }
        return path
    }
}

/// Read-only goal map (§4.8): goal, principles, systems, milestones, sustaining system. Zoom 0.6x to 2.0x.
/// Tapping a node calls `onSelect` with the entity id (the detail view then shows the Outline at that row).
struct GoalMapView: View {
    let goalID: UUID
    let onSelect: (UUID) -> Void
    let onEdit: (() -> Void)?

    @Environment(AppServices.self) private var services
    @State private var availableWidth: CGFloat = 358
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var contentHeight: CGFloat = 0

    init(goalID: UUID, onSelect: @escaping (UUID) -> Void = { _ in }, onEdit: (() -> Void)? = nil) {
        self.goalID = goalID
        self.onSelect = onSelect
        self.onEdit = onEdit
    }

    var body: some View {
        let _ = services.store.revision
        let snapshot = services.store.snapshot()
        let layout = ScheduleEngine.mapLayout(goalID: goalID, snapshot: snapshot)
        let goal = snapshot.goal(goalID)
        let today = LocalDay.today
        let late = goal.map { ScheduleEngine.backSchedule(objectives: snapshot.objectives(goalID: goalID), goal: $0, today: today).startsLateByDays } ?? [:]
        let width = canvasWidth(layout)

        ScrollView([.horizontal, .vertical]) {
            canvas(layout: layout, snapshot: snapshot, goal: goal, late: late, today: today, width: width)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    contentHeight = newHeight
                }
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: width * scale,
                       height: contentHeight > 0 ? contentHeight * scale : nil,
                       alignment: .topLeading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width - 32
        } action: { newWidth in
            availableWidth = max(newWidth, 200)
        }
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    scale = clamp(baseScale * value.magnification)
                }
                .onEnded { _ in
                    baseScale = scale
                }
        )
        .overlay(alignment: .bottomTrailing) { zoomControls }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onEdit?()
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit outline")
            }
        }
    }

    // MARK: Layout

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(GoalsMapMetrics.maxScale, max(GoalsMapMetrics.minScale, value))
    }

    private func nodeWidth(count: Int) -> CGFloat {
        let n = CGFloat(max(count, 1))
        return max(GoalsMapMetrics.minNodeWidth, (availableWidth - (n - 1) * GoalsMapMetrics.gap) / n)
    }

    private func layerWidth(count: Int) -> CGFloat {
        let n = CGFloat(max(count, 1))
        return n * nodeWidth(count: count) + (n - 1) * GoalsMapMetrics.gap
    }

    private func canvasWidth(_ layout: MapLayout) -> CGFloat {
        var width = availableWidth
        for layer in layout.layers where !layer.isEmpty {
            width = max(width, layerWidth(count: layer.count))
        }
        return width
    }

    private var zoomControls: some View {
        HStack(spacing: 8) {
            Button {
                scale = clamp(scale - 0.2)
                baseScale = scale
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .accessibilityLabel("Zoom out")
            .disabled(scale <= GoalsMapMetrics.minScale)
            Button {
                scale = clamp(scale + 0.2)
                baseScale = scale
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .accessibilityLabel("Zoom in")
            .disabled(scale >= GoalsMapMetrics.maxScale)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.textPrimary)
        .padding(16)
    }

    // MARK: Canvas

    private func canvas(layout: MapLayout, snapshot: StoreSnapshot, goal: Goal?, late: [UUID: Int],
                        today: LocalDay, width: CGFloat) -> some View {
        let now = Date()
        let week = Week(containing: HabitEngine.logicalDay(for: now))
        return VStack(alignment: .leading, spacing: GoalsMapMetrics.layerSpacing) {
            ForEach(layout.layers.indices, id: \.self) { index in
                let layer = layout.layers[index]
                if !layer.isEmpty {
                    HStack(alignment: .top, spacing: GoalsMapMetrics.gap) {
                        ForEach(layer) { node in
                            nodeView(node, width: nodeWidth(count: layer.count), dashed: false, snapshot: snapshot,
                                     goal: goal, late: late, today: today, week: week, now: now)
                        }
                    }
                }
            }
            if let sustaining = layout.sustaining {
                nodeView(sustaining, width: width, dashed: true, snapshot: snapshot,
                         goal: goal, late: late, today: today, week: week, now: now)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .coordinateSpace(.named(GoalsMapMetrics.spaceName))
        .backgroundPreferenceValue(GoalsMapFrameKey.self) { frames in
            GoalsMapEdges(frames: frames, edges: layout.edges)
                .stroke(Color.markMStroke, lineWidth: 1.2)
        }
    }

    private func nodeView(_ node: MapLayout.Node, width: CGFloat, dashed: Bool, snapshot: StoreSnapshot,
                          goal: Goal?, late: [UUID: Int], today: LocalDay, week: Week, now: Date) -> some View {
        let state = nodeState(node, snapshot: snapshot, today: today, week: week, now: now)
        let title = nodeTitle(node, goal: goal)
        let lateDays = node.kind == .objective ? late[node.id] : nil
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                onSelect(node.id)
            } label: {
                MapNode(title: title, state: state, dashed: dashed, kind: kindName(node.kind))
                    .frame(width: width)
            }
            .buttonStyle(.plain)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: GoalsMapFrameKey.self,
                        value: [node.id: proxy.frame(in: .named(GoalsMapMetrics.spaceName))]
                    )
                }
            }
            if let lateDays {
                Text(GoalsFormat.startsLate(lateDays))
                    .font(.caption2)
                    .foregroundStyle(Color.emberText)
                    .frame(width: width, alignment: .leading)
            }
        }
    }

    private func nodeTitle(_ node: MapLayout.Node, goal: Goal?) -> String {
        if node.kind == .goal, let goal {
            return "Goal: \(GoalsFormat.withUnit(goal.resultTarget, goal.resultUnit))"
        }
        return node.title
    }

    private func nodeState(_ node: MapLayout.Node, snapshot: StoreSnapshot, today: LocalDay, week: Week, now: Date) -> MapNodeState {
        switch node.kind {
        case .goal, .principle:
            return .neutral
        case .system:
            let status = HabitEngine.systemStatus(systemID: node.id, habits: snapshot.habits, week: week,
                                                  logs: snapshot.logs, now: now, settings: snapshot.settings)
            switch status {
            case .onTrack: return .onTrack
            case .behind: return .behind
            case .neutral: return .neutral
            }
        case .objective:
            guard let objective = snapshot.objective(node.id) else { return .neutral }
            if objective.status == .done { return .done }
            if let deadline = objective.deadline, deadline < today { return .behind }
            return .neutral
        }
    }

    private func kindName(_ kind: MapLayout.NodeKind) -> String {
        switch kind {
        case .goal: "Goal"
        case .principle: "Principle"
        case .system: "System"
        case .objective: "Milestone"
        }
    }
}

#Preview {
    NavigationStack { GoalMapView(goalID: SampleData.goalID) }
        .environment(AppServices.preview())
        .environment(Router())
}
