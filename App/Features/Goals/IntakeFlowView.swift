import SwiftUI
import CoreKit

/// Goal intake (§4.2, §4.3, §7.6): four question rounds, a review page, then "Send to Claude" which copies the prompt,
/// tries to open Claude and moves on to Import inside the same sheet. Presented bare from `RootTabView`, so it owns
/// its NavigationStack. The draft lives in `@SceneStorage` as JSON until an import succeeds or the user discards it.
struct IntakeFlowView: View {
    @Environment(AppServices.self) private var services
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @SceneStorage("goals.intake.draft") private var draftJSON = ""
    @SceneStorage("goals.intake.round") private var storedRound = 0

    @State private var answers = IntakeAnswers.defaults(today: LocalDay.today, settings: AppSettings.defaults)
    @State private var round = 0
    @State private var isLoaded = false
    @State private var showDiscard = false
    @State private var isSending = false
    @State private var showImport = false
    @State private var customPlace = ""
    @State private var otherStopper = ""
    @State private var showOtherStopper = false

    private let reviewRound = 4

    init() {}

    var body: some View {
        NavigationStack {
            NightCanvas {
                VStack(spacing: 0) {
                    progressHeader
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            page
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                        .id(round)
                        .transition(.opacity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle("New goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showDiscard = true }
                }
            }
            .navigationDestination(isPresented: $showImport) {
                ImportPlanView(goalID: nil, embedded: true, onImported: { clearDraft() })
            }
            .confirmationDialog("Discard this goal?", isPresented: $showDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    clearDraft()
                    router.sheet = nil
                }
                Button("Keep editing", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { loadIfNeeded() }
        .onChange(of: answers) { _, newValue in saveDraft(newValue) }
        .onChange(of: round) { _, newRound in storedRound = newRound }
    }

    // MARK: Header and bar

    private var progressHeader: some View {
        let step = min(round, 3) + 1
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(step)/4")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(roundName)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            ProgressView(value: Double(round >= reviewRound ? 4 : step), total: 4)
                .tint(Color.cobalt)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step) of 4, \(roundName)")
    }

    private var roundName: String {
        switch round {
        case 0: "The goal"
        case 1: "Your situation"
        case 2: "Time and place"
        case 3: "What breaks it"
        default: "Review"
        }
    }

    private var canAdvance: Bool {
        guard round == 0 else { return true }
        return !GoalsFormat.trimmed(answers.goal).isEmpty
            && !GoalsFormat.trimmed(answers.resultName).isEmpty
            && !GoalsFormat.trimmed(answers.unit).isEmpty
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if round > 0 {
                Button("Back") { go(round - 1) }
                    .buttonStyle(GoalsSolidButtonStyle(prominent: false))
            }
            if round < reviewRound {
                Button("Next") { go(round + 1) }
                    .buttonStyle(GoalsSolidButtonStyle())
                    .disabled(!canAdvance)
            } else {
                Button {
                    send()
                } label: {
                    if isSending {
                        ProgressView()
                    } else {
                        Text("Send to Claude")
                    }
                }
                .buttonStyle(GoalsSolidButtonStyle())
                .disabled(isSending)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.canvas)
    }

    private func go(_ target: Int) {
        let clamped = min(max(target, 0), reviewRound)
        if reduceMotion {
            round = clamped
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { round = clamped }
        }
    }

    // MARK: Pages

    @ViewBuilder
    private var page: some View {
        switch round {
        case 0: roundOne
        case 1: roundTwo
        case 2: roundThree
        case 3: roundFour
        default: review
        }
    }

    private var roundOne: some View {
        VStack(alignment: .leading, spacing: 20) {
            GoalsQuestion("What do you want?") {
                TextField("10% body fat", text: $answers.goal)
                    .modifier(GoalsFieldModifier())
            }
            GoalsQuestion("How will you measure it?") {
                VStack(spacing: 8) {
                    TextField("Weigh-in average", text: $answers.resultName)
                        .modifier(GoalsFieldModifier())
                    TextField("kg", text: $answers.unit)
                        .modifier(GoalsFieldModifier())
                }
            }
            GoalsQuestion("Where are you now?") {
                GoalsNumberField("0", value: $answers.current)
                    .modifier(GoalsFieldModifier())
            }
            GoalsQuestion("Where do you need to be?",
                          caption: "Direction: \(answers.direction == .down ? "down" : "up")") {
                GoalsNumberField("0", value: $answers.target)
                    .modifier(GoalsFieldModifier())
            }
            GoalsQuestion("By when?") {
                GoalsDayPicker("Deadline", day: $answers.deadline, minimum: LocalDay.today)
                    .modifier(GoalsFieldModifier())
            }
        }
    }

    private var roundTwo: some View {
        VStack(alignment: .leading, spacing: 20) {
            GoalsQuestion("What have you tried before, and why did it stop?", caption: "Optional") {
                TextField("", text: $answers.triedBefore, axis: .vertical)
                    .lineLimit(2...6)
                    .modifier(GoalsFieldModifier())
            }
            GoalsQuestion("What do you have to work with?") {
                TextField("Uni gym, £30 a month, a friend who lifts", text: $answers.resources, axis: .vertical)
                    .lineLimit(2...6)
                    .modifier(GoalsFieldModifier())
            }
            GoalsQuestion("Any hard limits?", caption: "Optional") {
                TextField("Knee injury, no cooking on Tuesdays", text: $answers.hardLimits, axis: .vertical)
                    .lineLimit(2...6)
                    .modifier(GoalsFieldModifier())
            }
            GoalsQuestion("Why does this matter to you?", caption: "Optional") {
                TextField("", text: $answers.whyItMatters, axis: .vertical)
                    .lineLimit(2...6)
                    .modifier(GoalsFieldModifier())
            }
        }
    }

    private var roundThree: some View {
        VStack(alignment: .leading, spacing: 20) {
            GoalsQuestion("Hours a week you can give this") {
                Stepper(value: $answers.hoursPerWeek, in: 1...20) {
                    Text("\(answers.hoursPerWeek) hours a week")
                        .foregroundStyle(Color.textPrimary)
                }
                .modifier(GoalsFieldModifier())
            }
            GoalsQuestion("When do you work best?") {
                LazyVGrid(columns: chipColumns, spacing: 8) {
                    ForEach(IntakeAnswers.TimeChip.allCases, id: \.self) { chip in
                        GoalsChip(title: chip.label, isOn: answers.bestTimes.contains(chip)) {
                            toggleTime(chip)
                        }
                    }
                }
            }
            GoalsQuestion("Where do you work best?") {
                VStack(alignment: .leading, spacing: 8) {
                    LazyVGrid(columns: chipColumns, spacing: 8) {
                        ForEach(placeOptions, id: \.self) { place in
                            GoalsChip(title: place, isOn: answers.bestPlaces.contains(place)) {
                                togglePlace(place)
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("Add a place", text: $customPlace)
                            .modifier(GoalsFieldModifier())
                            .onSubmit { addPlace() }
                        Button("Add") { addPlace() }
                            .buttonStyle(GoalsSolidButtonStyle(prominent: false))
                            .frame(width: 90)
                            .disabled(GoalsFormat.trimmed(customPlace).isEmpty)
                    }
                }
            }
            GoalsQuestion("Keep Saturdays off for goal work?", caption: "Physical habits are still allowed.") {
                Toggle("Saturdays off", isOn: $answers.saturdaysOff)
                    .foregroundStyle(Color.textPrimary)
                    .modifier(GoalsFieldModifier())
            }
        }
    }

    private var roundFour: some View {
        VStack(alignment: .leading, spacing: 20) {
            GoalsQuestion("What usually makes you stop?") {
                VStack(alignment: .leading, spacing: 8) {
                    LazyVGrid(columns: chipColumns, spacing: 8) {
                        ForEach(IntakeAnswers.stopperChips, id: \.self) { chip in
                            GoalsChip(title: chip, isOn: answers.stoppers.contains(chip)) {
                                toggleStopper(chip)
                            }
                        }
                        GoalsChip(title: "Other", isOn: showOtherStopper) {
                            showOtherStopper.toggle()
                            if !showOtherStopper { otherStopper = "" }
                            rebuildStoppers()
                        }
                    }
                    if showOtherStopper {
                        TextField("What else?", text: $otherStopper)
                            .modifier(GoalsFieldModifier())
                            .onChange(of: otherStopper) { _, _ in rebuildStoppers() }
                    }
                }
            }
            GoalsQuestion("What's the smallest version you'd still do on a bad day?", caption: "Optional") {
                TextField("", text: $answers.badDayVersion, axis: .vertical)
                    .lineLimit(2...6)
                    .modifier(GoalsFieldModifier())
            }
        }
    }

    private var chipColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 130), spacing: 8)]
    }

    private var placeOptions: [String] {
        IntakeAnswers.placeChips + answers.bestPlaces.filter { !IntakeAnswers.placeChips.contains($0) }
    }

    // MARK: Review

    private var review: some View {
        VStack(alignment: .leading, spacing: 12) {
            reviewCard("The goal", editRound: 0, lines: [
                answers.goal,
                "Measured by \(answers.resultName) (\(answers.unit)). Now \(GoalsFormat.number(answers.current)), target \(GoalsFormat.number(answers.target)).",
                "By \(LockInFormat.dayMonth(answers.deadline))"
            ])
            reviewCard("Your situation", editRound: 1, lines: [
                "Tried before: \(orDash(answers.triedBefore))",
                "Resources: \(orDash(answers.resources))",
                "Hard limits: \(orDash(answers.hardLimits))",
                "Why it matters: \(orDash(answers.whyItMatters))"
            ])
            reviewCard("Time and place", editRound: 2, lines: [
                "\(answers.hoursPerWeek) hours a week",
                "Best times: \(listOrDash(answers.bestTimes.map(\.label)))",
                "Best places: \(listOrDash(answers.bestPlaces))",
                "Saturdays off: \(answers.saturdaysOff ? "yes" : "no")"
            ])
            reviewCard("What breaks it", editRound: 3, lines: [
                "Usually stops me: \(listOrDash(answers.stoppers))",
                "Bad-day version: \(orDash(answers.badDayVersion))"
            ])
            Text("Send to Claude copies everything above plus your busy times for the next 14 days (no event titles).")
                .font(.footnote)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func reviewCard(_ title: String, editRound: Int, lines: [String]) -> some View {
        GoalsCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Button("Edit") { go(editRound) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.cobaltText)
                        .frame(minHeight: 44)
                }
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    private func orDash(_ text: String) -> String {
        let trimmed = GoalsFormat.trimmed(text)
        return trimmed.isEmpty ? "—" : trimmed
    }

    private func listOrDash(_ items: [String]) -> String {
        items.isEmpty ? "—" : items.joined(separator: ", ")
    }

    // MARK: Chips

    private func toggleTime(_ chip: IntakeAnswers.TimeChip) {
        if let index = answers.bestTimes.firstIndex(of: chip) {
            answers.bestTimes.remove(at: index)
        } else {
            answers.bestTimes.append(chip)
        }
    }

    private func togglePlace(_ place: String) {
        if let index = answers.bestPlaces.firstIndex(of: place) {
            answers.bestPlaces.remove(at: index)
        } else {
            answers.bestPlaces.append(place)
        }
    }

    private func addPlace() {
        let place = GoalsFormat.trimmed(customPlace)
        guard !place.isEmpty else { return }
        if !answers.bestPlaces.contains(place) { answers.bestPlaces.append(place) }
        customPlace = ""
    }

    private func toggleStopper(_ chip: String) {
        if let index = answers.stoppers.firstIndex(of: chip) {
            answers.stoppers.remove(at: index)
        } else {
            answers.stoppers.append(chip)
        }
        rebuildStoppers()
    }

    /// The chips picked, plus the free-text "Other" answer when it is on.
    private func rebuildStoppers() {
        var list = answers.stoppers.filter { IntakeAnswers.stopperChips.contains($0) }
        let other = GoalsFormat.trimmed(otherStopper)
        if showOtherStopper && !other.isEmpty { list.append(other) }
        if list != answers.stoppers { answers.stoppers = list }
    }

    // MARK: Draft

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        if !draftJSON.isEmpty,
           let data = draftJSON.data(using: .utf8),
           let saved = try? JSONDecoder().decode(IntakeAnswers.self, from: data) {
            answers = saved
            round = min(max(storedRound, 0), reviewRound)
        } else {
            answers = IntakeAnswers.defaults(today: LocalDay.today, settings: services.store.snapshot().settings)
        }
        if let custom = answers.stoppers.first(where: { !IntakeAnswers.stopperChips.contains($0) }) {
            otherStopper = custom
            showOtherStopper = true
        }
    }

    private func saveDraft(_ value: IntakeAnswers) {
        guard isLoaded, let data = try? JSONEncoder().encode(value) else { return }
        draftJSON = String(decoding: data, as: UTF8.self)
    }

    private func clearDraft() {
        draftJSON = ""
        storedRound = 0
    }

    // MARK: Send

    private func send() {
        guard !isSending else { return }
        isSending = true
        Task {
            var busy: [BusyInterval]? = nil
            if services.calendar.status == .granted {
                let start = LocalDay.today.date()
                let range = DateInterval(start: start, end: LocalDay.today.adding(days: 14).date())
                busy = await services.calendar.busyIntervals(in: range)
            }
            let prompt = PromptBuilder.intakePrompt(answers: answers, busy: busy,
                                                    settings: services.store.snapshot().settings, now: Date())
            await ClaudeHandoff.send(prompt, router: router)
            isSending = false
            showImport = true
        }
    }
}

/// A question: title, optional caption, then the field(s).
private struct GoalsQuestion<Content: View>: View {
    let title: String
    let caption: String?
    private let content: Content

    init(_ title: String, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.sectionTitle)
                .foregroundStyle(Color.textPrimary)
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(Color.textTertiary)
            }
            content
        }
    }
}

#Preview {
    IntakeFlowView()
        .environment(AppServices.preview())
        .environment(Router())
}
