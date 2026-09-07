import SwiftUI

struct CreativeWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore
    @Environment(\.interfaceScale) private var interfaceScale
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var seed = ""
    @State private var instruction = ""
    @State private var batchCount = 1
    @State private var chapterCount = 20
    @State private var disabledStepIDs: Set<String> = []
    @State private var excludedContextIDs: Set<String> = []
    @State private var showPromptPreview = false
    @State private var showDiff = false
    @State private var showWorkspaceOverview = true

    var body: some View {
        if model.project.creativeWorkspace == nil {
            landing
        } else {
            HStack(spacing: 0) {
                libraryColumn.frame(width: layoutScaled(250))
                Divider()
                workflowColumn.frame(width: layoutScaled(350))
                Divider()
                editorColumn
            }
        }
    }

    private var landing: some View {
        VStack {
            Spacer()
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.auraViolet, Color.brand],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: scaled(88), height: scaled(88))
                        .shadow(color: Color.auraViolet.opacity(0.34), radius: 28, y: 10)
                    Image(systemName: "pencil.and.scribble")
                        .scaledFont(size: 39, weight: .medium)
                        .foregroundStyle(.white)
                }
                Text(localization.text("从灵感到连载成稿"))
                    .scaledFont(size: 31, weight: .bold)
                Text(localization.text("六条固定工作流、作者确认点、章节版本和本地资料库。"))
                    .foregroundStyle(Color.secondaryText)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button(localization.text("新建网文项目")) { model.createCreativeProject() }
                        .buttonStyle(PrimaryButtonStyle())
                    Button(localization.text("导入已有原稿")) { model.chooseCreativeSource() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Text(localization.text("未配置模型时仍可编辑、检查和导出；生成步骤会等待 BYOK 模型。"))
                    .scaledFont(size: 11)
                    .foregroundStyle(Color.secondaryText)
                Label(
                    localization.text("也可以将文件拖到窗口任意位置"),
                    systemImage: "arrow.down.doc"
                )
                .scaledFont(size: 11)
                .foregroundStyle(Color.secondaryText)
            }
            .padding(.horizontal, 54)
            .padding(.vertical, 48)
            .scaledFrame(maxWidth: 680)
            .auraSurface(.elevated, cornerRadius: 28)
            .shadow(color: Color.auraBlue.opacity(0.12), radius: 38, y: 18)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var libraryColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(localization.text("工作流模板"))
                .scaledFont(size: 10, weight: .bold)
                .foregroundStyle(Color.secondaryText)
                .padding(.horizontal, 14)
                .padding(.top, 14)
            ScrollView {
                VStack(spacing: 6) {
                    Button {
                        showWorkspaceOverview = true
                        model.selectedCreativeChapterID = nil
                        model.selectedCreativeRunID = nil
                    } label: {
                        Label(localization.text("创作资料库"), systemImage: "tray.full.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(showWorkspaceOverview ? Color.brand.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(AuraPlainButtonStyle())
                    ForEach(CreativeWorkflowRegistry.definitions) { definition in
                        Button {
                            showWorkspaceOverview = false
                            model.selectedCreativeWorkflow = definition.id
                            disabledStepIDs = []
                            model.refreshCreativePromptPreview(seed: seed, instruction: instruction)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: definition.symbol).frame(width: scaled(20))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(localization.text(definition.id.title))
                                        .scaledFont(size: 12, weight: .semibold)
                                    Text(localization.text(definition.summary))
                                        .scaledFont(size: 9)
                                        .lineLimit(2)
                                        .foregroundStyle(Color.secondaryText)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(model.selectedCreativeWorkflow == definition.id
                                ? Color.brand.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(AuraPlainButtonStyle())
                    }
                }
                .padding(10)

                Divider().padding(.horizontal, 12)
                HStack {
                    Text(localization.text("章节"))
                        .scaledFont(size: 10, weight: .bold)
                        .foregroundStyle(Color.secondaryText)
                    Spacer()
                    Text("\(workspace.chapters.count)")
                        .scaledFont(size: 9, design: .monospaced)
                }
                .padding(14)
                VStack(spacing: 4) {
                    ForEach(workspace.chapters.sorted { $0.number < $1.number }) { chapter in
                        Button {
                            showWorkspaceOverview = false
                            model.selectCreativeChapter(chapter.id)
                        } label: {
                            HStack(spacing: 8) {
                                chapterStatusIndicator(chapter.status)
                                Text(chapterLabel(chapter.number))
                                    .scaledFont(size: 10, design: .monospaced)
                                Text(localization.documentUnitTitle(chapter.title)).scaledFont(size: 11).lineLimit(1)
                                Spacer()
                                if chapter.candidateVersionID != nil {
                                    Text(localization.text("待确认"))
                                        .scaledFont(size: 8, weight: .bold)
                                        .foregroundStyle(Color.brand)
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(minHeight: scaled(32))
                            .background(model.selectedCreativeChapterID == chapter.id
                                ? Color.brand.opacity(0.1) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(AuraPlainButtonStyle())
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            }
        }
        .background {
            AuraSurface(level: .panel)
        }
    }

    private var workflowColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                let definition = CreativeWorkflowRegistry.definition(model.selectedCreativeWorkflow)
                Label(localization.text(definition.id.title), systemImage: definition.symbol)
                    .scaledFont(size: 20, weight: .bold)
                Text(localization.text(definition.summary))
                    .scaledFont(size: 11)
                    .foregroundStyle(Color.secondaryText)

                if model.selectedCreativeWorkflow == .incubation {
                    field(localization.text("灵感或题材")) {
                        TextEditor(text: $seed)
                            .auraTextEditor()
                            .scaledFrame(minHeight: 82)
                    }
                }
                if model.selectedCreativeWorkflow == .outline {
                    Stepper("\(localization.text("规划章节"))：\(chapterCount)", value: $chapterCount, in: 1...200)
                }
                if [.chapterProduction, .continuityAudit].contains(model.selectedCreativeWorkflow) {
                    Stepper("\(localization.text("本批章节"))：\(batchCount)", value: $batchCount, in: 1...10)
                }
                field(localization.text("本次运行补充")) {
                    TextEditor(text: $instruction)
                        .auraTextEditor()
                        .scaledFrame(minHeight: 70)
                }

                DisclosureGroup(localization.text("可选步骤与上下文")) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(definition.steps.filter(\.isOptional)) { step in
                            Toggle(
                                localization.text(step.title),
                                isOn: Binding(
                                    get: { !disabledStepIDs.contains(step.id) },
                                    set: { enabled in
                                        if enabled { disabledStepIDs.remove(step.id) }
                                        else { disabledStepIDs.insert(step.id) }
                                    }
                                )
                            )
                        }
                        ForEach(model.creativeContextOptions()) { context in
                            Toggle(
                                localization.text(context.label),
                                isOn: Binding(
                                    get: { !excludedContextIDs.contains(context.id) },
                                    set: { enabled in
                                        if enabled { excludedContextIDs.remove(context.id) }
                                        else { excludedContextIDs.insert(context.id) }
                                    }
                                )
                            )
                            .scaledFont(size: 10)
                        }
                    }
                    .padding(.top, 8)
                }

                field(localization.text("项目级创作规则")) {
                    TextEditor(text: Binding(
                        get: { workspace.projectPromptInstructions[model.selectedCreativeWorkflow] ?? "" },
                        set: { model.updateCreativeProjectInstruction($0, workflowID: model.selectedCreativeWorkflow) }
                    ))
                    .auraTextEditor()
                    .scaledFrame(minHeight: 64)
                }

                HStack {
                    Button(localization.text("预览最终提示词")) {
                        model.refreshCreativePromptPreview(seed: seed, instruction: instruction)
                        showPromptPreview.toggle()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    Button(localization.text("开始运行")) {
                        model.startCreativeWorkflow(
                            seed: seed,
                            instruction: instruction,
                            batchCount: batchCount,
                            chapterCount: chapterCount,
                            disabledStepIDs: disabledStepIDs,
                            excludedContextIDs: excludedContextIDs
                        )
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isCreativeRunning)
                }

                if showPromptPreview {
                    Text(model.creativePromptPreview)
                        .scaledFont(size: 9, design: .monospaced)
                        .textSelection(.enabled)
                        .padding(10)
                        .auraSurface(.editor, cornerRadius: 9)
                }

                if let run = selectedRun {
                    Divider()
                    HStack {
                        Text(localization.text("当前运行"))
                            .scaledFont(size: 13, weight: .bold)
                        Spacer()
                        statusBadge(run.status)
                    }
                    if !run.modelNames.isEmpty {
                        Text("Pro: \(run.modelNames[.primary] ?? "—") · Flash: \(run.modelNames[.flash] ?? "—") · \(run.endpointHost ?? "local")")
                            .scaledFont(size: 9, design: .monospaced)
                            .foregroundStyle(Color.secondaryText)
                    }
                    VStack(spacing: 6) {
                        ForEach(Array(run.steps.enumerated()), id: \.element.id) { index, step in
                            HStack(spacing: 8) {
                                Image(systemName: stepIcon(step.status))
                                    .foregroundStyle(stepColor(step.status))
                                Text(localization.text(step.title)).scaledFont(size: 10)
                                Spacer()
                                if index == run.activeStepIndex {
                                    Text(localization.text("当前"))
                                        .scaledFont(size: 8, weight: .bold)
                                        .foregroundStyle(Color.brand)
                                }
                            }
                        }
                    }
                    runActions(run)
                }

                if !model.creativeRuns.isEmpty {
                    Divider()
                    Text(localization.text("运行历史"))
                        .scaledFont(size: 12, weight: .bold)
                    ForEach(model.creativeRuns.prefix(12)) { run in
                        Button {
                            showWorkspaceOverview = false
                            model.selectedCreativeRunID = run.id
                        } label: {
                            HStack {
                                Text(localization.text(run.workflowID.title)).scaledFont(size: 10)
                                Spacer()
                                Text(run.updatedAt.formatted(date: .omitted, time: .shortened))
                                statusBadge(run.status)
                            }
                        }
                        .buttonStyle(AuraPlainButtonStyle())
                    }
                }
            }
            .padding(16)
        }
        .background(Color.workspace)
    }

    @ViewBuilder
    private var editorColumn: some View {
        if showWorkspaceOverview {
            workspaceOverview
        } else if let chapter = selectedChapter {
            chapterEditor(chapter)
        } else if let artifact = latestArtifact {
            artifactPreview(artifact)
        } else {
            workspaceOverview
        }
    }

    private func chapterEditor(_ chapter: ChapterDocument) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(chapterLabel(chapter.number)) · \(localization.documentUnitTitle(chapter.title))")
                        .scaledFont(size: 18, weight: .bold)
                    Text("\(textUnitCount(model.creativeEditorText)) \(textUnitLabel) · \(localization.text(chapter.status.rawValue))")
                        .scaledFont(size: 10)
                        .foregroundStyle(Color.secondaryText)
                }
                Spacer()
                if chapter.candidateVersionID != nil {
                    Button(localization.text("对比")) { showDiff.toggle() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button(localization.text("拒绝")) { model.rejectCreativeChapterCandidate(chapter.id) }
                        .buttonStyle(SecondaryButtonStyle())
                    Button(localization.text("接受并继续")) { model.acceptCreativeChapterCandidate(chapter.id) }
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button(localization.text("保存版本")) { model.saveCreativeChapterVersion() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(16)
            Divider()
            if showDiff, chapter.candidateVersionID != nil,
               let accepted = chapter.versions.last(where: { $0.accepted }) {
                VStack(spacing: 0) {
                    HSplitView {
                        readOnlyText(model.creativeChapterVersionText(accepted), title: localization.text("当前正式版"))
                        editableText(title: localization.text("候选稿"))
                    }
                    Divider()
                    paragraphDiff(
                        CreativeParagraphDiff.compare(
                            model.creativeChapterVersionText(accepted),
                            model.creativeEditorText
                        )
                    )
                    .scaledFrame(height: 120)
                }
            } else {
                TextEditor(text: Binding(
                    get: { model.creativeEditorText },
                    set: model.updateCreativeEditorText
                ))
                .auraTextEditor()
                .scaledFont(size: 14)
                .padding(20)
                .background(Color.editorPaper)
            }
            Divider()
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Text(localization.text("版本"))
                        .scaledFont(size: 10, weight: .bold)
                    ForEach(chapter.versions.reversed()) { version in
                        Button {
                            model.restoreCreativeChapterVersion(version.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(localization.text(version.source.rawValue))
                                Text(version.createdAt.formatted(date: .numeric, time: .shortened))
                                    .foregroundStyle(Color.secondaryText)
                            }
                            .scaledFont(size: 9)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .help(localization.text("恢复会创建新版本，不覆盖历史"))
                    }
                }
                .padding(10)
            }
        }
    }

    private func artifactPreview(_ artifact: WorkflowArtifactReference) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(localization.text(artifact.title)).scaledFont(size: 20, weight: .bold)
                    Text(localizedArtifactSummary(artifact.summary)).foregroundStyle(Color.secondaryText)
                }
                Spacer()
                if artifact.isCandidate, let run = selectedRun, run.status == .waitingForApproval {
                    Button(localization.text("重新生成")) { model.regenerateCreativeRun(run.id) }
                        .buttonStyle(SecondaryButtonStyle())
                    Button(localization.text("接受并继续")) { model.approveCreativeRun(run.id) }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            Divider()
            ScrollView {
                Text(model.creativeArtifactMarkdown(artifact))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(18)
            }
            .auraSurface(.editor, cornerRadius: 12)
        }
        .padding(18)
        .background(Color.workspace)
    }

    private func localizedArtifactSummary(_ value: String) -> String {
        let parts = value.components(separatedBy: "、")
        guard parts.count > 1 else { return localization.text(value) }
        return parts.map(localization.text).joined(separator: localization.language == .english ? ", " : "、")
    }

    private func localizedMetadataTitle(_ value: String) -> String {
        localization.text(localization.documentUnitTitle(value))
    }

    private var workspaceOverview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(localization.text("创作资料库")).scaledFont(size: 22, weight: .bold)
                    Spacer()
                    Menu(localization.text("导出")) {
                        Button("DOCX") { model.exportCreative(.docx) }
                        Button("Markdown") { model.exportCreative(.markdown) }
                        Button("JSON") { model.exportCreative(.json) }
                    }
                    Button(localization.text("移交到改编工坊")) { model.requestCreativeHandoff() }
                        .buttonStyle(PrimaryButtonStyle())
                }
                if let brief = workspace.activeBrief {
                    DisclosureGroup(localization.text("新书企划")) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField(localization.text("题材"), text: briefBinding(brief, \.genre))
                            TextField(localization.text("基调"), text: briefBinding(brief, \.tone))
                            TextEditor(text: briefBinding(brief, \.premise))
                                .auraTextEditor()
                                .scaledFrame(minHeight: 70)
                        }.padding(.top, 8)
                    }.panelCard()
                } else {
                    summaryCard(localization.text("新书企划"), localization.text("尚未生成"))
                }
                if let bible = workspace.activeStoryBible {
                    DisclosureGroup("\(localization.text("故事圣经")) · \(bible.cards.count) \(localization.text("张卡片"))") {
                        VStack(spacing: 8) {
                            ForEach(bible.cards) { card in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(localization.text(card.kind.title)).scaledFont(size: 9, weight: .bold).foregroundStyle(Color.brand)
                                        TextField(localization.text("名称"), text: bibleCardBinding(card, \.name))
                                        Toggle(localization.text("向模型可见"), isOn: bibleVisibilityBinding(card))
                                            .toggleStyle(.checkbox)
                                    }
                                    TextEditor(text: bibleCardBinding(card, \.summary))
                                        .auraTextEditor()
                                        .scaledFrame(minHeight: 48)
                                }
                                .padding(10)
                                .auraSurface(.editor, cornerRadius: 9)
                            }
                        }.padding(.top, 8)
                    }.panelCard()
                }
                ForEach(workspace.outlines) { outline in
                    DisclosureGroup("\(localization.text("卷章规划")) · \(localizedMetadataTitle(outline.title))") {
                        VStack(spacing: 8) {
                            ForEach(outline.chapterCards) { card in
                                VStack(alignment: .leading, spacing: 5) {
                                    TextField(chapterLabel(card.number), text: chapterCardTitleBinding(card))
                                        .scaledFont(size: 11, weight: .bold)
                                    TextField(localization.text("章节目标"), text: chapterCardBinding(card, \.objective))
                                    TextField(localization.text("冲突"), text: chapterCardBinding(card, \.conflict))
                                    TextField(localization.text("结尾钩子"), text: chapterCardBinding(card, \.hook))
                                }
                                .padding(9)
                                .auraSurface(.editor, cornerRadius: 9)
                            }
                        }.padding(.top, 8)
                    }.panelCard()
                }
                if !workspace.continuityIssues.isEmpty {
                    DisclosureGroup("\(localization.text("连续性问题")) · \(workspace.continuityIssues.count)") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(workspace.continuityIssues) { issue in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(issue.category).scaledFont(size: 11, weight: .bold)
                                    Text(issue.evidence).scaledFont(size: 10)
                                    Text(issue.suggestion).scaledFont(size: 10).foregroundStyle(Color.secondaryText)
                                }
                            }
                        }.padding(.top, 8)
                    }.panelCard()
                }
            }
            .padding(20)
        }
        .background(Color.workspace)
    }

    @ViewBuilder
    private func runActions(_ run: WorkflowRun) -> some View {
        HStack {
            if run.status == .waitingForApproval {
                Button(localization.text("重新生成")) { model.regenerateCreativeRun(run.id) }
                    .buttonStyle(SecondaryButtonStyle())
                Button(localization.text("接受并继续")) { model.approveCreativeRun(run.id) }
                    .buttonStyle(PrimaryButtonStyle())
            } else if [.waitingForModel, .interrupted, .failed].contains(run.status) {
                Button(localization.text("继续 / 重试")) { model.resumeCreativeRun(run.id) }
                    .buttonStyle(PrimaryButtonStyle())
            }
            if ![.completed, .cancelled].contains(run.status) {
                Button(localization.text("停止工作流")) { model.cancelCreativeRun(run.id) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).scaledFont(size: 10, weight: .semibold).foregroundStyle(Color.secondaryText)
            content()
                .padding(7)
                .auraSurface(.editor, cornerRadius: 8)
        }
    }

    private func summaryCard(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).scaledFont(size: 12, weight: .bold)
            Text(detail).scaledFont(size: 11).foregroundStyle(Color.secondaryText)
        }.panelCard()
    }

    private func briefBinding(_ brief: CreativeBrief, _ keyPath: WritableKeyPath<CreativeBrief, String>) -> Binding<String> {
        Binding(
            get: { workspace.activeBrief?[keyPath: keyPath] ?? "" },
            set: { value in
                var updated = workspace.activeBrief ?? brief
                updated[keyPath: keyPath] = value
                model.updateCreativeBrief(updated)
            }
        )
    }

    private func bibleCardBinding(_ card: StoryBibleCard, _ keyPath: WritableKeyPath<StoryBibleCard, String>) -> Binding<String> {
        Binding(
            get: {
                workspace.activeStoryBible?.cards.first(where: { $0.id == card.id })?[keyPath: keyPath] ?? ""
            },
            set: { value in
                var updated = workspace.activeStoryBible?.cards.first(where: { $0.id == card.id }) ?? card
                updated[keyPath: keyPath] = value
                model.updateCreativeStoryBibleCard(updated)
            }
        )
    }

    private func bibleVisibilityBinding(_ card: StoryBibleCard) -> Binding<Bool> {
        Binding(
            get: {
                workspace.activeStoryBible?.cards.first(where: { $0.id == card.id })?.visibility == .included
            },
            set: { included in
                var updated = workspace.activeStoryBible?.cards.first(where: { $0.id == card.id }) ?? card
                updated.visibility = included ? .included : .hidden
                model.updateCreativeStoryBibleCard(updated)
            }
        )
    }

    private func chapterCardBinding(_ card: ChapterCard, _ keyPath: WritableKeyPath<ChapterCard, String>) -> Binding<String> {
        Binding(
            get: {
                workspace.outlines.flatMap(\.chapterCards).first(where: { $0.id == card.id })?[keyPath: keyPath] ?? ""
            },
            set: { value in
                var updated = workspace.outlines.flatMap(\.chapterCards).first(where: { $0.id == card.id }) ?? card
                updated[keyPath: keyPath] = value
                model.updateCreativeChapterCard(updated)
            }
        )
    }

    private func chapterCardTitleBinding(_ card: ChapterCard) -> Binding<String> {
        Binding(
            get: {
                let value = workspace.outlines.flatMap(\.chapterCards)
                    .first(where: { $0.id == card.id })?.title ?? card.title
                return localization.documentUnitTitle(value)
            },
            set: { value in
                var updated = workspace.outlines.flatMap(\.chapterCards)
                    .first(where: { $0.id == card.id }) ?? card
                updated.title = value
                model.updateCreativeChapterCard(updated)
            }
        )
    }

    private func readOnlyText(_ value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).scaledFont(size: 10, weight: .bold).padding(.horizontal, 12).padding(.top, 10)
            ScrollView { Text(value).frame(maxWidth: .infinity, alignment: .topLeading).padding(12) }
        }.background(Color.workspace)
    }

    private func editableText(title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).scaledFont(size: 10, weight: .bold).padding(.horizontal, 12).padding(.top, 10)
            TextEditor(text: Binding(
                get: { model.creativeEditorText },
                set: model.updateCreativeEditorText
            ))
            .auraTextEditor()
            .padding(8)
        }.background(Color.editorPaper)
    }

    private func paragraphDiff(_ entries: [ParagraphDiffEntry]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(entries.filter { $0.kind != .unchanged }) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.kind == .added ? "+" : "−")
                            .scaledFont(size: 10, weight: .bold, design: .monospaced)
                        Text(entry.text).scaledFont(size: 10).textSelection(.enabled)
                    }
                    .foregroundStyle(entry.kind == .added ? Color.green : Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
        }
        .background(Color.workspace)
    }

    private func statusBadge(_ status: WorkflowRunStatus) -> some View {
        Text(statusLabel(status))
            .scaledFont(size: 8, weight: .bold)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(statusColor(status).opacity(0.14))
            .foregroundStyle(statusColor(status))
            .clipShape(Capsule())
    }

    private func statusLabel(_ status: WorkflowRunStatus) -> String {
        switch status {
        case .queued: localization.text("排队")
        case .running: localization.text("运行中")
        case .waitingForModel: localization.text("等待模型")
        case .waitingForApproval: localization.text("等待确认")
        case .interrupted: localization.text("已中断")
        case .failed: localization.text("失败")
        case .completed: localization.text("完成")
        case .cancelled: localization.text("已取消")
        }
    }

    private func statusColor(_ status: WorkflowRunStatus) -> Color {
        switch status {
        case .completed: .green
        case .failed: .red
        case .waitingForApproval, .waitingForModel: .orange
        case .running: Color.brand
        default: Color.secondaryText
        }
    }

    private func stepIcon(_ status: WorkflowStepStatus) -> String {
        switch status {
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .running: "circle.dotted"
        case .waiting: "pause.circle.fill"
        case .skipped: "minus.circle"
        case .pending: "circle"
        }
    }

    private func stepColor(_ status: WorkflowStepStatus) -> Color {
        switch status {
        case .completed: .green
        case .failed: .red
        case .running, .waiting: Color.brand
        default: Color.secondaryText
        }
    }

    private func chapterStatusColor(_ status: ChapterStatus) -> Color {
        switch status {
        case .accepted: .green
        case .review: .orange
        case .drafting: Color.brand
        case .planned: Color.secondaryText
        }
    }

    @ViewBuilder
    private func chapterStatusIndicator(_ status: ChapterStatus) -> some View {
        if differentiateWithoutColor {
            Image(systemName: chapterStatusSymbol(status))
                .scaledFont(size: 9, weight: .bold)
                .foregroundStyle(chapterStatusColor(status))
                .frame(width: scaled(12), height: scaled(12))
                .accessibilityLabel(localization.text(status.rawValue))
        } else {
            Circle()
                .fill(chapterStatusColor(status))
                .frame(width: scaled(7), height: scaled(7))
                .accessibilityLabel(localization.text(status.rawValue))
        }
    }

    private func chapterStatusSymbol(_ status: ChapterStatus) -> String {
        switch status {
        case .accepted: "checkmark.circle.fill"
        case .review: "exclamationmark.circle.fill"
        case .drafting: "pencil.circle.fill"
        case .planned: "circle.dashed"
        }
    }

    private func chapterLabel(_ number: Int) -> String {
        localization.text("第 {{number}} 章", ["number": number])
    }

    private var textUnitLabel: String {
        localization.text(model.resolvedContentLanguage == .english ? "词" : "字")
    }

    private func textUnitCount(_ value: String) -> Int {
        if model.resolvedContentLanguage == .english {
            return value.split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }.count
        }
        return value.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        InterfaceScalePolicy.scaled(value, by: interfaceScale)
    }

    private func layoutScaled(_ value: CGFloat) -> CGFloat {
        InterfaceScalePolicy.layoutScaled(value, by: interfaceScale)
    }

    private var workspace: CreativeWorkspace { model.project.creativeWorkspace ?? CreativeWorkspace() }
    private var selectedRun: WorkflowRun? {
        model.creativeRuns.first(where: { $0.id == model.selectedCreativeRunID }) ?? model.creativeRuns.first
    }
    private var selectedChapter: ChapterDocument? {
        guard let id = model.selectedCreativeChapterID else { return nil }
        return workspace.chapters.first(where: { $0.id == id })
    }
    private var latestArtifact: WorkflowArtifactReference? {
        guard let run = selectedRun else { return workspace.artifacts.last(where: { $0.kind != .promptSnapshot }) }
        return workspace.artifacts.last(where: { $0.runID == run.id && $0.kind != .promptSnapshot })
    }
}
