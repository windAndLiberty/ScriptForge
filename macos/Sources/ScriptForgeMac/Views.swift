import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: 238)
                Divider()
                VStack(spacing: 0) {
                    HeaderView()
                    Divider()
                    content
                }
                .background(Color.workspace)
            }

            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.82))
                    .clipShape(Capsule())
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView()
                .environmentObject(model)
                .environmentObject(localization)
        }
        .alert(
            localization.text("永久删除项目"),
            isPresented: Binding(
                get: { model.pendingDelete != nil },
                set: { if !$0 { model.pendingDelete = nil } }
            )
        ) {
            Button(localization.text("取消"), role: .cancel) { model.pendingDelete = nil }
            Button(localization.text("确认删除"), role: .destructive) { model.confirmDelete() }
        } message: {
            Text(localization.text("此操作不可撤销。项目文件和全部生成资产都会被删除。"))
        }
        .alert(
            "ScriptForge",
            isPresented: Binding(
                get: { model.presentedError != nil },
                set: { if !$0 { model.presentedError = nil } }
            )
        ) {
            Button("OK") { model.presentedError = nil }
        } message: {
            Text(model.presentedError ?? "")
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
    }

    @ViewBuilder
    private var content: some View {
        switch model.primaryView {
        case .bookAnalysis:
            BookAnalysisView()
        case .studio:
            StudioView()
        case .projects:
            ProjectArchiveView()
        case .prompts:
            PromptAssetsView()
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.brand)
                    Image(systemName: "text.book.closed.fill").foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(localization.text("剧擎"))
                        .font(.system(size: 17, weight: .bold))
                    Text("SCRIPT FORGE")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)

            VStack(spacing: 5) {
                nav(.bookAnalysis, "一键拆书", "wand.and.stars")
                nav(.studio, "改编工坊", "hammer.fill")
                nav(.projects, "项目档案", "archivebox.fill")
                nav(.prompts, "提示词资产", "text.quote")
            }
            .padding(.horizontal, 10)

            Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 16)

            Text(localization.text("当前项目"))
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.42))
                .padding(.horizontal, 18)

            Button {
                model.primaryView = .studio
            } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.brand.opacity(0.22))
                        .overlay(Image(systemName: "doc.text.fill").foregroundStyle(Color.brandLight))
                        .frame(width: 38, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.project.document?.title ?? localization.text("尚未导入"))
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(2)
                        Text(model.project.document == nil
                            ? localization.text("导入小说")
                            : "\(model.project.chapterCount) chapters · \(model.project.generatedEpisodeCount) episodes")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.48))
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Color.white.opacity(model.primaryView == .studio ? 0.09 : 0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(10)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Label(localization.text("本地优先"), systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(localization.text("数据保存在此 Mac"))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.48))
            }
            .padding(18)
        }
        .foregroundStyle(.white)
        .background(Color.sidebar)
    }

    private func nav(_ view: PrimaryView, _ title: String, _ icon: String) -> some View {
        Button {
            model.primaryView = view
        } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).frame(width: 20)
                Text(localization.text(title)).font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .foregroundStyle(model.primaryView == view ? .white : Color.white.opacity(0.62))
            .background(model.primaryView == view ? Color.brand.opacity(0.88) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct HeaderView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(sectionTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
                if model.project.document != nil && model.primaryView == .studio {
                    TextField(
                        "",
                        text: Binding(
                            get: { model.project.name },
                            set: model.updateProjectName
                        )
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: 460)
                } else {
                    Text(localization.text(pageName))
                        .font(.system(size: 18, weight: .bold))
                }
            }
            Spacer()
            if model.project.result != nil && model.primaryView == .studio {
                Button(localization.text("导出成稿")) { model.exportScript() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            Picker("", selection: $localization.language) {
                ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 104)
            Button { model.showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(IconButtonStyle())
            Button(localization.text("重置")) { model.resetToHome() }
                .buttonStyle(SecondaryButtonStyle())
                .help(localization.text("重置") + " → Home")
        }
        .padding(.horizontal, 22)
        .frame(height: 66)
        .background(Color.panel)
    }

    private var sectionTitle: String {
        switch model.primaryView {
        case .bookAnalysis: "CREATION SYSTEM / BOOK ANALYSIS"
        case .studio: "CREATION SYSTEM / ADAPTATION"
        case .projects: "LOCAL WORKSPACE / PROJECTS"
        case .prompts: "CREATION SYSTEM / PROMPTS"
        }
    }

    private var pageName: String {
        switch model.primaryView {
        case .bookAnalysis: "一键拆书"
        case .studio: "改编工坊"
        case .projects: "项目档案"
        case .prompts: "提示词资产"
        }
    }
}

private struct StudioView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.project.document == nil {
            EmptyHomeView()
        } else {
            HStack(spacing: 0) {
                StudioInspectorView()
                    .frame(width: 340)
                Divider()
                VStack(spacing: 0) {
                    PipelineProgressView()
                    StudioTabsView()
                    Divider()
                    Group {
                        switch model.activeTab {
                        case .outline: EpisodeOutlineView()
                        case .bible: StoryBibleView()
                        case .script: ScriptEditorView()
                        case .quality: QualityReportView()
                        }
                    }
                }
            }
        }
    }
}

private struct EmptyHomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().fill(Color.brand.opacity(0.1)).frame(width: 114, height: 114)
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.brand)
            }
            Text(localization.text("把长篇故事，锻造成能拍的短剧。"))
                .font(.system(size: 30, weight: .bold))
            Text(localization.text("先建立证据和故事圣经，再规划、成稿、终审与定向修复。"))
                .font(.system(size: 14))
                .foregroundStyle(Color.secondaryText)
            Button {
                model.chooseNovel()
            } label: {
                Label(localization.text("导入小说"), systemImage: "square.and.arrow.down")
                    .padding(.horizontal, 24)
                    .frame(height: 42)
            }
            .buttonStyle(PrimaryButtonStyle())
            Text(localization.text("支持 UTF-8 TXT，可拖入窗口"))
                .font(.system(size: 11))
                .foregroundStyle(Color.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StudioInspectorView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                inspectorSection(localization.text("原著章节")) {
                    if let document = model.project.document {
                        HStack {
                            metric("\(document.chapters.count)", "chapters")
                            metric("\(document.characterCount)", "characters")
                        }
                        Picker("", selection: $model.selectedChapter) {
                            ForEach(Array(document.chapters.enumerated()), id: \.offset) { index, chapter in
                                Text("\(chapter.index). \(chapter.title)").tag(index)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        if document.chapters.indices.contains(model.selectedChapter) {
                            Text(document.chapters[model.selectedChapter].content)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondaryText)
                                .lineLimit(8)
                                .padding(10)
                                .background(Color.workspace)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                inspectorSection(localization.text("人物新名")) {
                    if model.isNaming {
                        Label(localization.text("人物命名中…"), systemImage: "sparkles")
                            .foregroundStyle(Color.brand)
                    }
                    ForEach(model.project.characters) { character in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(character.sourceName)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.secondaryText)
                                Image(systemName: "arrow.right").font(.system(size: 9))
                                TextField(
                                    "",
                                    text: Binding(
                                        get: {
                                            model.project.characters.first(where: { $0.id == character.id })?.targetName ?? character.targetName
                                        },
                                        set: { model.updateCharacter(id: character.id, targetName: $0) }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                            }
                            Text(character.role + " · " + character.nameSource.rawValue)
                                .font(.system(size: 9))
                                .foregroundStyle(Color.secondaryText)
                        }
                    }
                }

                inspectorSection(localization.text("改编规格")) {
                    Stepper(
                        value: Binding(
                            get: { model.project.options.episodeCount },
                            set: { value in model.updateOptions { $0.episodeCount = value } }
                        ),
                        in: 1...100
                    ) {
                        specRow(localization.text("目标集数"), "\(model.project.options.episodeCount)")
                    }
                    Picker(
                        localization.text("单集时长"),
                        selection: Binding(
                            get: { model.project.options.durationSeconds },
                            set: { value in model.updateOptions { $0.durationSeconds = value } }
                        )
                    ) {
                        ForEach([60, 90, 120], id: \.self) { Text("\($0)s").tag($0) }
                    }
                    Text(localization.text("场次数由模型动态决定"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.brand)
                    TextField(
                        localization.text("题材"),
                        text: Binding(
                            get: { model.project.options.genre },
                            set: { value in model.updateOptions { $0.genre = value } }
                        )
                    )
                    TextField(
                        localization.text("基调"),
                        text: Binding(
                            get: { model.project.options.tone },
                            set: { value in model.updateOptions { $0.tone = value } }
                        )
                    )
                    Picker(
                        localization.text("创作策略"),
                        selection: Binding(
                            get: { model.project.options.trendPreset },
                            set: { value in model.updateOptions { $0.trendPreset = value } }
                        )
                    ) {
                        ForEach(TrendPreset.allCases) { Text(localization.text($0.rawValue)).tag($0) }
                    }
                }

                VStack(spacing: 10) {
                    Button {
                        model.runAdaptation()
                    } label: {
                        HStack {
                            if model.isRunning { ProgressView().controlSize(.small) }
                            Text(localization.text(model.project.result == nil ? "开始改编" : "重新生成"))
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isRunning || model.isNaming)

                    if model.isRunning {
                        Button(localization.text("取消任务")) { model.cancelCurrentTask() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Label(
                        localization.text(model.modelReady ? "双模型可信管线" : "本地基础管线"),
                        systemImage: model.modelReady ? "bolt.shield.fill" : "laptopcomputer"
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
                }
            }
            .padding(18)
        }
        .background(Color.panel)
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(Color.secondaryText)
            content()
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 18, weight: .bold))
            Text(label).font(.system(size: 9)).foregroundStyle(Color.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func specRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).fontWeight(.bold) }
    }
}

private struct PipelineProgressView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(model.pipelineProgress.detail.isEmpty ? "Pipeline ready" : model.pipelineProgress.detail)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(Int(model.pipelineProgress.fraction * 100))%")
                    .font(.system(size: 11, weight: .bold))
            }
            ProgressView(value: model.pipelineProgress.fraction)
                .tint(Color.brand)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(Color.panel)
    }
}

private struct StudioTabsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        HStack(spacing: 5) {
            tab(.outline, "分集设计", "rectangle.grid.1x2")
            tab(.bible, "故事圣经", "network")
            tab(.script, "剧本编辑", "doc.text")
            tab(.quality, "质检报告", "checkmark.shield")
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(Color.panel)
    }

    private func tab(_ value: StudioTab, _ title: String, _ icon: String) -> some View {
        Button {
            model.activeTab = value
        } label: {
            Label(localization.text(title), systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 11)
                .frame(height: 30)
                .foregroundStyle(model.activeTab == value ? Color.brand : Color.secondaryText)
                .background(model.activeTab == value ? Color.brand.opacity(0.09) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

private struct EpisodeOutlineView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        if let result = model.project.result {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(result.episodes) { episode in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("EP \(episode.number)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.brand)
                                Text("《\(episode.title)》").font(.system(size: 16, weight: .bold))
                                Spacer()
                                Label(
                                    "\(episode.scenes.count) " + localization.text("动态场次"),
                                    systemImage: "camera.fill"
                                )
                                .font(.system(size: 10))
                                .foregroundStyle(Color.secondaryText)
                            }
                            HStack(alignment: .top, spacing: 10) {
                                contractCell("冷开场", episode.openingHook)
                                contractCell("本集目标", episode.objective)
                                contractCell("中段反转", episode.reversal)
                                contractCell("结尾卡点", episode.endHook)
                            }
                            Text(episode.contract.transitionFromPrevious)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.secondaryText)
                        }
                        .panelCard()
                    }
                }
                .padding(20)
            }
        } else {
            EmptyState(icon: "rectangle.grid.1x2", title: localization.text("尚未生成剧本"))
        }
    }

    private func contractCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(localization.text(label)).font(.system(size: 9, weight: .bold)).foregroundStyle(Color.brand)
            Text(value).font(.system(size: 11)).lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(9)
        .background(Color.workspace)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct StoryBibleView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        if let bible = model.project.result?.storyBible {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(bible.premise).font(.system(size: 16, weight: .semibold)).panelCard()
                    bibleSection("Characters") {
                        ForEach(bible.canonicalCharacters) { character in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(character.scriptName).fontWeight(.bold)
                                Text(character.role + " · " + character.relationships.joined(separator: "；"))
                                    .font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                            }
                        }
                    }
                    bibleSection("World Rules") {
                        ForEach(bible.worldRules) { rule in
                            Text("• \(rule.subject)：\(rule.fact)（\(rule.cause)）").font(.system(size: 11))
                        }
                    }
                    bibleSection("Timeline") {
                        ForEach(bible.timeline) { event in
                            Text("\(event.order). \(event.event) → \(event.effect)").font(.system(size: 11))
                        }
                    }
                }
                .padding(20)
            }
        } else {
            EmptyState(icon: "network", title: localization.text("尚未生成剧本"))
        }
    }

    private func bibleSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.brand)
            content()
        }
        .panelCard()
    }
}

private struct ScriptEditorView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        if let result = model.project.result, !result.episodes.isEmpty {
            HStack(spacing: 0) {
                List {
                    ForEach(Array(result.episodes.enumerated()), id: \.offset) { index, episode in
                        Button {
                            model.selectedEpisode = index
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("EP \(episode.number) · \(episode.title)").fontWeight(.semibold)
                                Text("\(episode.scenes.count) scenes · \(episode.runtime?.estimatedSeconds ?? 0, specifier: "%.1f")s")
                                    .font(.system(size: 9)).foregroundStyle(Color.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .background(model.selectedEpisode == index ? Color.brand.opacity(0.08) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.sidebar)
                .frame(width: 220)
                Divider()
                if result.episodes.indices.contains(model.selectedEpisode) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("EP \(result.episodes[model.selectedEpisode].number)")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.brand)
                            Spacer()
                            Text(localization.text("剧本编辑"))
                                .font(.system(size: 10)).foregroundStyle(Color.secondaryText)
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 42)
                        TextEditor(
                            text: Binding(
                                get: {
                                    guard let latest = model.project.result,
                                          latest.episodes.indices.contains(model.selectedEpisode) else { return "" }
                                    return latest.episodes[model.selectedEpisode].content
                                },
                                set: model.updateEpisodeContent
                            )
                        )
                        .font(.system(size: 14, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(18)
                        .background(Color.editorPaper)
                    }
                }
            }
        } else {
            EmptyState(icon: "doc.text", title: localization.text("尚未生成剧本"))
        }
    }
}

private struct QualityReportView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        if let quality = model.project.result?.quality {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 18) {
                        VStack(alignment: .leading) {
                            Text("\(quality.score)").font(.system(size: 44, weight: .bold))
                            Text(localization.text("综合分")).foregroundStyle(Color.secondaryText)
                        }
                        Divider().frame(height: 54)
                        Label(
                            localization.text(quality.passed ? "达到交付线" : "需要人工复核"),
                            systemImage: quality.passed ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
                        )
                        .foregroundStyle(quality.passed ? Color.green : Color.orange)
                        Spacer()
                        if let gate = quality.gate {
                            VStack(alignment: .trailing) {
                                Text("\(gate.openIssueCount)").font(.system(size: 22, weight: .bold))
                                Text(localization.text("开放问题")).font(.system(size: 10)).foregroundStyle(Color.secondaryText)
                            }
                        }
                    }
                    .panelCard()

                    ForEach(quality.metrics) { metric in
                        HStack(spacing: 12) {
                            Circle().fill(metric.level.color).frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(metric.label).fontWeight(.semibold)
                                Text(metric.detail).font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                            }
                            Spacer()
                            Text("\(metric.score)").font(.system(size: 18, weight: .bold))
                        }
                        .panelCard()
                    }

                    if let issues = quality.gate?.issues.filter({ !$0.resolved }), !issues.isEmpty {
                        Text(localization.text("开放问题")).font(.system(size: 16, weight: .bold))
                        ForEach(issues) { issue in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(issue.severity.rawValue.uppercased())
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(issue.severity == .blocker ? Color.red : Color.orange)
                                    Text("EP " + issue.episodeNumbers.map(String.init).joined(separator: ", "))
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                Text(issue.evidence).font(.system(size: 12))
                                Text("→ " + issue.repairInstruction)
                                    .font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                            }
                            .panelCard()
                        }
                    }
                }
                .padding(20)
            }
        } else {
            EmptyState(icon: "checkmark.shield", title: localization.text("尚未生成剧本"))
        }
    }
}

private struct BookAnalysisView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore
    @State private var revisionInstruction = ""

    var body: some View {
        if model.project.document == nil {
            EmptyHomeView()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(localization.text("拆书报告"))
                                .font(.system(size: 26, weight: .bold))
                            Text(model.project.document?.title ?? "")
                                .foregroundStyle(Color.secondaryText)
                        }
                        Spacer()
                        if model.project.bookAnalysis != nil {
                            Button(localization.text("导出报告")) { model.exportBookAnalysis() }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        Button {
                            model.runBookAnalysis()
                        } label: {
                            Label(
                                localization.text(model.project.bookAnalysis == nil ? "开始一键拆书" : "重新一键拆书"),
                                systemImage: "wand.and.stars"
                            )
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(model.isRunning)
                    }

                    if model.isRunning || model.bookProgress.fraction > 0 {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(model.bookProgress.detail.isEmpty
                                    ? localization.text("准备开始一键拆书")
                                    : model.bookProgress.detail)
                                Spacer()
                                Text("\(Int(model.bookProgress.fraction * 100))%")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            ProgressView(value: model.bookProgress.fraction).tint(Color.brand)
                        }
                        .panelCard()
                    }

                    if let report = model.project.bookAnalysis {
                        HStack(spacing: 12) {
                            metricCard(localization.text("证据覆盖"), "\(report.coveragePercent)%")
                            metricCard("Mode", report.mode.rawValue.uppercased())
                            metricCard("Versions", "\(model.project.bookAnalysisVersions.count)/8")
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(report.logline).font(.system(size: 16, weight: .semibold))
                            Text(report.summary).font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                            Text(report.genreTags.joined(separator: " · "))
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.brand)
                        }
                        .panelCard()
                        ForEach(report.sections) { section in
                            VStack(alignment: .leading, spacing: 9) {
                                Text(section.title).font(.system(size: 17, weight: .bold))
                                Text(section.markdown).font(.system(size: 12)).textSelection(.enabled)
                                Text("Evidence: " + section.evidenceChapterIDs.joined(separator: " · "))
                                    .font(.system(size: 9)).foregroundStyle(Color.secondaryText)
                            }
                            .panelCard()
                        }
                        VStack(alignment: .leading, spacing: 9) {
                            Text(localization.text("修订指令")).fontWeight(.bold)
                            TextEditor(text: $revisionInstruction)
                                .frame(minHeight: 74)
                                .padding(8)
                                .background(Color.workspace)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            Button(localization.text("提交微调")) {
                                model.reviseBookAnalysis(instruction: revisionInstruction)
                                revisionInstruction = ""
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(!model.modelReady || revisionInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .panelCard()
                    } else {
                        EmptyState(icon: "wand.and.stars", title: localization.text("准备开始一键拆书"))
                            .frame(height: 360)
                    }
                }
                .padding(24)
            }
        }
    }

    private func metricCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 22, weight: .bold))
            Text(title).font(.system(size: 10)).foregroundStyle(Color.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard()
    }
}

private struct ProjectArchiveView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore
    @State private var selected = LibraryView.recent

    private enum LibraryView: Equatable { case recent, archived }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(localization.text("项目档案")).font(.system(size: 27, weight: .bold))
                        Text(localization.text("最近最多保留50个，超出后自动归档；归档项目不会自动删除。"))
                            .foregroundStyle(Color.secondaryText)
                    }
                    Spacer()
                    Button(localization.text("新建项目")) { model.newProject() }
                        .buttonStyle(PrimaryButtonStyle())
                }

                HStack(spacing: 12) {
                    summaryButton("\(model.recentProjects.count)", "最近项目", selected == .recent) { selected = .recent }
                    summaryButton("\(model.archivedProjects.count)", "已归档", selected == .archived) { selected = .archived }
                    summaryStatic("\(model.projectLibrary.reduce(0) { $0 + $1.chapterCount })", "累计章节")
                    summaryStatic("\(model.projectLibrary.reduce(0) { $0 + $1.generatedEpisodeCount })", "已生成集数")
                }

                let visible = selected == .recent ? model.recentProjects : model.archivedProjects
                if visible.isEmpty {
                    EmptyState(icon: "archivebox", title: localization.text("没有项目"))
                        .frame(height: 340)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 14)], spacing: 14) {
                        ForEach(visible) { project in
                            projectCard(project)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func summaryButton(_ value: String, _ title: String, _ active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            summaryContent(value, title)
                .background(active ? Color.brand.opacity(0.1) : Color.panel)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Color.brand : Color.border))
        }
        .buttonStyle(.plain)
    }

    private func summaryStatic(_ value: String, _ title: String) -> some View {
        summaryContent(value, title)
            .background(Color.panel)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.border))
    }

    private func summaryContent(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(size: 24, weight: .bold))
            Text(localization.text(title)).font(.system(size: 10)).foregroundStyle(Color.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func projectCard(_ project: StoredProject) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.brand.opacity(0.1))
                    .overlay(Image(systemName: "doc.richtext.fill").foregroundStyle(Color.brand))
                    .frame(width: 46, height: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name).font(.system(size: 14, weight: .bold)).lineLimit(2)
                    Text(project.document?.title ?? localization.text("尚未导入"))
                        .font(.system(size: 10)).foregroundStyle(Color.secondaryText)
                }
                Spacer()
            }
            HStack {
                Label("\(project.chapterCount)", systemImage: "book.pages")
                Label("\(project.generatedEpisodeCount)", systemImage: "play.rectangle")
                Spacer()
                Text(project.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.system(size: 9)).foregroundStyle(Color.secondaryText)
            Divider()
            HStack(spacing: 8) {
                Button(localization.text("打开")) { model.openProject(project) }
                    .buttonStyle(SecondaryButtonStyle())
                Button(localization.text("创建副本")) { model.duplicateProject(project) }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                if project.archivedAt == nil {
                    Button(localization.text("归档")) { model.archiveProject(project) }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button(localization.text("恢复")) { model.restoreProject(project) }
                        .buttonStyle(SecondaryButtonStyle())
                    Button(role: .destructive) { model.requestDelete(project) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(IconButtonStyle())
                }
            }
        }
        .panelCard()
        .contentShape(Rectangle())
        .onTapGesture { model.openProject(project) }
    }
}

private struct PromptAssetsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore
    @State private var selectedID: String? = PromptAssets.defaults.first?.id

    var body: some View {
        HStack(spacing: 0) {
            List(model.promptAssets, selection: $selectedID) { asset in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(asset.title).fontWeight(.semibold)
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondaryText)
                            .help(localization.text("影响范围") + "：" + asset.influence)
                    }
                    Text(asset.scope).font(.system(size: 9)).foregroundStyle(Color.secondaryText)
                }
                .tag(asset.id)
            }
            .listStyle(.sidebar)
            .frame(width: 270)
            Divider()
            if let asset = model.promptAssets.first(where: { selectedID == $0.id }) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(asset.title).font(.system(size: 22, weight: .bold))
                            Text(asset.scope).foregroundStyle(Color.secondaryText)
                        }
                        Spacer()
                        Button(localization.text("恢复默认")) { model.resetPromptAsset(id: asset.id) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Label(asset.influence, systemImage: "info.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.brand)
                        .padding(10)
                        .background(Color.brand.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    TextEditor(
                        text: Binding(
                            get: {
                                model.promptAssets.first(where: { $0.id == asset.id })?.instruction ?? ""
                            },
                            set: { model.updatePromptAsset(id: asset.id, instruction: $0) }
                        )
                    )
                    .font(.system(size: 13, design: .monospaced))
                    .padding(12)
                    .background(Color.editorPaper)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.border))
                }
                .padding(24)
            }
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore
    @Environment(\.dismiss) private var dismiss
    @State private var settings: ModelSettings
    @State private var apiKey = ""
    @State private var consentGranted: Bool

    init() {
        _settings = State(initialValue: ModelSettings())
        _consentGranted = State(initialValue: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(localization.text("模型与安全设置")).font(.system(size: 21, weight: .bold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(IconButtonStyle())
            }
            Toggle(localization.text("启用在线双模型管线"), isOn: $settings.useOnline)
            settingField("API Base URL") { TextField("https://api.openai.com/v1", text: $settings.baseURL) }
            settingField("创作模型（Pro）") { TextField("gpt-5.6-sol", text: $settings.primaryModel) }
            settingField("高速模型（Flash）") { TextField("gpt-5.6-terra", text: $settings.flashModel) }
            settingField("推理强度") {
                Picker("", selection: $settings.reasoningEffort) {
                    ForEach(["none", "low", "medium", "high"], id: \.self) { Text($0).tag($0) }
                }.labelsHidden()
            }
            settingField("API Key") {
                SecureField(model.hasAPIKey ? "•••••••• (saved)" : "sk-…", text: $apiKey)
            }
            Toggle(localization.text("同意发送到当前端点"), isOn: $consentGranted)
            Text(localization.text("在线改编会把所选小说片段发送到上方域名。密钥仅保存在 macOS Keychain。"))
                .font(.system(size: 11))
                .foregroundStyle(Color.secondaryText)
                .padding(10)
                .background(Color.workspace)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Button(localization.text("取消")) { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                Button(localization.text("保存连接")) {
                    model.saveSettings(settings, apiKey: apiKey, consentGranted: consentGranted)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(settings.useOnline && !consentGranted)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            settings = model.modelSettings
            consentGranted = model.modelSettings.hasEndpointConsent
        }
    }

    private func settingField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(localization.text(title)).frame(width: 150, alignment: .leading)
            content().textFieldStyle(.roundedBorder)
        }
    }
}

private struct EmptyState: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 36)).foregroundStyle(Color.brand.opacity(0.7))
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension View {
    func panelCard() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.panel)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.border))
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(configuration.isPressed ? Color.brand.opacity(0.75) : Color.brand)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.primaryText)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(configuration.isPressed ? Color.border : Color.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.border))
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primaryText)
            .frame(width: 32, height: 32)
            .background(configuration.isPressed ? Color.border : Color.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.border))
    }
}

private extension QualityLevel {
    var color: Color {
        switch self {
        case .good: .green
        case .warning: .orange
        case .bad: .red
        }
    }
}

private extension Color {
    static let brand = Color(red: 0.78, green: 0.23, blue: 0.16)
    static let brandLight = Color(red: 0.96, green: 0.54, blue: 0.42)
    static let sidebar = Color(red: 0.10, green: 0.11, blue: 0.12)
    static let workspace = Color(red: 0.95, green: 0.94, blue: 0.91)
    static let panel = Color(red: 0.985, green: 0.98, blue: 0.965)
    static let editorPaper = Color(red: 0.99, green: 0.985, blue: 0.97)
    static let border = Color.black.opacity(0.09)
    static let primaryText = Color(red: 0.13, green: 0.14, blue: 0.15)
    static let secondaryText = Color(red: 0.39, green: 0.40, blue: 0.41)
}
