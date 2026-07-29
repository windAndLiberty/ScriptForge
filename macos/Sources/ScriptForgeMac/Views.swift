import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 218)

            VStack(spacing: 0) {
                TopBarView()
                Divider()

                if model.project.document == nil {
                    EmptyStateView()
                } else {
                    PipelineHeaderView()
                    Divider()
                    HSplitView {
                        SourcePanelView()
                            .frame(minWidth: 220, idealWidth: 250, maxWidth: 320)
                        StudioPanelView()
                            .frame(minWidth: 480)
                        CharacterPanelView()
                            .frame(minWidth: 260, idealWidth: 288, maxWidth: 340)
                    }
                }
            }
            .background(Color.workspace)
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $model.showSettings) {
            SettingsView()
                .environmentObject(model)
                .environmentObject(localization)
        }
        .alert(
            localization.text("生成失败"),
            isPresented: Binding(
                get: { model.presentedError != nil },
                set: { visible in
                    if !visible { model.presentedError = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.presentedError ?? "")
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
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.brand)
                    Image(systemName: "text.book.closed.fill")
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text(localization.text("剧擎"))
                        .font(.system(size: 17, weight: .bold))
                    Text(localization.text("改编工坊"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 28)

            sidebarLabel(localization.text("项目档案"))

            Button {
                model.activeTab = .outline
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.project.document?.title ?? localization.text("尚未导入"))
                            .lineLimit(1)
                        Text(
                            model.project.document == nil
                                ? localization.text("导入小说后开始")
                                : localization.text("当前项目")
                        )
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer(minLength: 0)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(12)
                .background(Color.white.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)

            Spacer()

            Button {
                model.showSettings = true
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                    Text(localization.text("模型与偏好"))
                    Spacer()
                    Circle()
                        .fill(model.hasAPIKey ? Color.green : Color.white.opacity(0.2))
                        .frame(width: 7, height: 7)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                VStack(alignment: .leading, spacing: 1) {
                    Text(localization.text("本地创作空间"))
                    Text(localization.text("数据保存在此 Mac"))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding(18)
        }
        .background(Color.sidebar)
    }

    private func sidebarLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(.white.opacity(0.35))
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
    }
}

private struct TopBarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.project.document?.title ?? localization.text("改编工坊"))
                    .font(.system(size: 15, weight: .semibold))
                Label(localization.text("本地已保存"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
            }

            Spacer()

            Picker(localization.text("语言"), selection: $localization.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.label).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 142)

            Button {
                model.chooseNovel()
            } label: {
                Label(localization.text("导入小说"), systemImage: "square.and.arrow.down")
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                model.exportScript()
            } label: {
                Label(localization.text("导出成稿"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.project.result == nil)
        }
        .padding(.horizontal, 20)
        .frame(height: 68)
        .background(Color.panel)
    }
}

private struct EmptyStateView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.brand.opacity(0.09))
                Image(systemName: "wand.and.stars.inverse")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.brand)
            }
            .frame(width: 76, height: 76)

            Text(localization.text("把长篇故事，锻造成能拍的短剧。"))
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(Color.primaryText)

            Text(
                localization.text(
                    "不再把整本小说塞进一次提示词。先建立故事事实、人物圣经和改名表，再规划分集、逐集生成并自动质检。"
                )
            )
            .font(.system(size: 13))
            .foregroundStyle(Color.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 610)
            .lineSpacing(4)

            Button {
                model.chooseNovel()
            } label: {
                Label(localization.text("导入小说文本"), systemImage: "doc.badge.plus")
            }
            .buttonStyle(PrimaryButtonStyle())

            Text(localization.text("支持 UTF-8 TXT / MD，可直接拖入窗口"))
                .font(.system(size: 11))
                .foregroundStyle(Color.secondaryText)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isTargeted ? Color.brand.opacity(0.08) : Color.workspace)
        .dropDestination(for: URL.self) { urls, _ in
            guard let first = urls.first else { return false }
            model.importNovel(from: first)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }
}

private struct PipelineHeaderView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    private let steps: [(PipelinePhase, String)] = [
        (.ingest, "文本拆解"),
        (.analysis, "故事事实"),
        (.characters, "人物改名"),
        (.outline, "分集规划"),
        (.drafting, "逐集成稿"),
        (.quality, "质量校验"),
    ]

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localization.text("结构化改编管线"))
                        .font(.system(size: 13, weight: .bold))
                    Text(
                        model.progressDetail.isEmpty
                            ? localization.text("人物表已就绪，确认改名后即可生成")
                            : localization.progressText(model.progressDetail)
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondaryText)
                }
                Spacer()
                Text("\(Int(model.progress * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.brand)
            }

            HStack(spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 5) {
                        HStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .fill(stepColor(item.0))
                                if isDone(item.0) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(.white)
                                } else {
                                    Text("\(index + 1)")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: 16, height: 16)
                            Text(localization.text(item.1))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.secondaryText)
                            if index < steps.count - 1 {
                                Rectangle()
                                    .fill(Color.border)
                                    .frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.panel)
    }

    private func phaseIndex(_ phase: PipelinePhase) -> Int {
        switch phase {
        case .idle: return -1
        case .ingest: return 0
        case .analysis: return 1
        case .characters: return 2
        case .outline: return 3
        case .drafting: return 4
        case .quality, .completed: return 5
        case .failed: return max(0, Int(model.progress * 6) - 1)
        }
    }

    private func isDone(_ phase: PipelinePhase) -> Bool {
        phaseIndex(model.project.phase) >= phaseIndex(phase)
    }

    private func stepColor(_ phase: PipelinePhase) -> Color {
        isDone(phase) ? Color.brand : Color.gray.opacity(0.35)
    }
}

private struct SourcePanelView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        VStack(spacing: 0) {
            if let document = model.project.document {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localization.text("原著章节"))
                            .font(.system(size: 13, weight: .bold))
                        Text(
                            localization.text(
                                "{{chapters}} 章节 · {{characters}} 字符",
                                [
                                    "chapters": document.chapters.count,
                                    "characters": document.characterCount.formatted(),
                                ]
                            )
                        )
                        .font(.system(size: 9))
                        .foregroundStyle(Color.secondaryText)
                    }
                    Spacer()
                }
                .padding(14)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(document.chapters.enumerated()), id: \.element.id) { index, chapter in
                            Button {
                                model.selectedChapter = index
                            } label: {
                                HStack(alignment: .top, spacing: 9) {
                                    Text(String(format: "%02d", chapter.index))
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(
                                            model.selectedChapter == index ? Color.brand : Color.secondaryText
                                        )
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(chapter.title)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Color.primaryText)
                                            .lineLimit(2)
                                        Text("\(chapter.characterCount.formatted()) \(localization.text("字符"))")
                                            .font(.system(size: 9))
                                            .foregroundStyle(Color.secondaryText)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(9)
                                .background(
                                    model.selectedChapter == index
                                        ? Color.brand.opacity(0.08)
                                        : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }

                if document.chapters.indices.contains(model.selectedChapter) {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(localization.text("原文预览"))
                            .font(.system(size: 8, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(Color.secondaryText)
                        Text(document.chapters[model.selectedChapter].content)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondaryText)
                            .lineLimit(6)
                            .lineSpacing(3)
                    }
                    .padding(12)
                }
            }
        }
        .background(Color.panel)
    }
}

private struct StudioPanelView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                studioTab(.outline, "分集设计", "rectangle.3.group")
                studioTab(.script, "剧本编辑", "text.alignleft")
                studioTab(.quality, "质检报告", "checkmark.shield")
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(Color.panel)

            Divider()

            Group {
                switch model.activeTab {
                case .outline:
                    OutlineView()
                case .script:
                    ScriptEditorView()
                case .quality:
                    QualityReportView()
                }
            }
        }
        .background(Color.workspace)
    }

    private func studioTab(_ tab: StudioTab, _ title: String, _ icon: String) -> some View {
        Button {
            model.activeTab = tab
        } label: {
            Label(localization.text(title), systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.activeTab == tab ? Color.brand : Color.secondaryText)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(model.activeTab == tab ? Color.brand.opacity(0.09) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

private struct OutlineView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let result = model.project.result {
                    ResultSummaryView(result: result)
                } else {
                    introduction
                }

                card {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionTitle("改编规格", icon: "dial.medium")

                        HStack(spacing: 12) {
                            numberField(
                                "目标集数",
                                value: $model.project.options.episodeCount,
                                range: 1...100,
                                suffix: localization.text("集")
                            )
                            numberField(
                                "单集时长",
                                value: $model.project.options.durationSeconds,
                                range: 30...300,
                                step: 10,
                                suffix: localization.text("秒")
                            )
                            numberField(
                                "每集场次",
                                value: $model.project.options.scenesPerEpisode,
                                range: 1...8,
                                suffix: localization.text("场")
                            )
                        }

                        HStack(spacing: 12) {
                            labeledTextField(
                                "题材",
                                text: $model.project.options.genre
                            )
                            labeledTextField(
                                "基调",
                                text: $model.project.options.tone
                            )
                        }
                    }
                }

                card {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("创作策略", icon: "sparkles")
                        Picker(
                            localization.text("创作策略"),
                            selection: $model.project.options.trendPreset
                        ) {
                            ForEach(TrendPreset.allCases) { preset in
                                Text(localization.text(preset.rawValue)).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        HStack(spacing: 18) {
                            strategyLabel("强钩子", "bolt.fill")
                            strategyLabel("高信息密度", "waveform.path.ecg")
                            strategyLabel("可拍性优先", "video.fill")
                        }
                    }
                }

                card {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            sectionTitle(
                                model.modelSettings.useOnline
                                    ? "结构化大模型管线"
                                    : "离线验收管线",
                                icon: model.modelSettings.useOnline ? "network" : "checkmark.circle"
                            )
                            Spacer()
                            Picker(
                                localization.text("生成模式"),
                                selection: $model.modelSettings.useOnline
                            ) {
                                Text(localization.text("离线验收")).tag(false)
                                Text(localization.text("在线精修")).tag(true)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 178)
                        }

                        Text(
                            localization.text(
                                "确认右侧角色新名与改编规格，系统将先规划全部分集，再逐集生成和校验。"
                            )
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondaryText)
                        .lineSpacing(3)

                        Button {
                            model.runPipeline()
                        } label: {
                            HStack {
                                if model.isRunning {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "play.fill")
                                }
                                Text(
                                    model.isRunning
                                        ? localization.text("正在运行…")
                                        : localization.text(
                                            model.project.result == nil ? "开始改编" : "重新生成"
                                        )
                                )
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(model.isRunning)
                    }
                }
            }
            .padding(18)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localization.text("人物改名表已预填"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.primaryText)
            Text(
                localization.text(
                    "确认右侧角色新名与改编规格，系统将先规划全部分集，再逐集生成和校验。"
                )
            )
            .font(.system(size: 12))
            .foregroundStyle(Color.secondaryText)
        }
    }

    private func numberField(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1,
        suffix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localization.text(title))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.secondaryText)
            HStack {
                Text("\(value.wrappedValue)")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                Text(suffix)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondaryText)
                Spacer()
                Stepper("", value: value, in: range, step: step)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color.workspace)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .frame(maxWidth: .infinity)
    }

    private func labeledTextField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localization.text(title))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.secondaryText)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color.workspace)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .frame(maxWidth: .infinity)
    }

    private func strategyLabel(_ title: String, _ icon: String) -> some View {
        Label(localization.text(title), systemImage: icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.secondaryText)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(localization.text(title), systemImage: icon)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.primaryText)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.panel)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.border, lineWidth: 1)
            )
    }
}

private struct ResultSummaryView: View {
    @EnvironmentObject private var localization: LocalizationStore
    let result: AdaptationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(localization.text("全剧规划已生成"))
                    .font(.system(size: 21, weight: .bold))
                Spacer()
                Label(
                    "\(result.quality.score)",
                    systemImage: result.quality.passed
                        ? "checkmark.seal.fill"
                        : "exclamationmark.triangle.fill"
                )
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(result.quality.passed ? Color.green : Color.orange)
            }
            Text(result.logline)
                .font(.system(size: 12))
                .foregroundStyle(Color.secondaryText)
                .lineSpacing(3)
        }
    }
}

private struct ScriptEditorView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        if let result = model.project.result, !result.episodes.isEmpty {
            HStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(Array(result.episodes.enumerated()), id: \.element.id) { index, episode in
                            Button {
                                model.selectedEpisode = index
                            } label: {
                                HStack(spacing: 8) {
                                    Text(String(format: "%02d", episode.number))
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(
                                            model.selectedEpisode == index
                                                ? Color.brand
                                                : Color.secondaryText
                                        )
                                    Text(episode.title)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color.primaryText)
                                        .lineLimit(2)
                                    Spacer(minLength: 0)
                                }
                                .padding(9)
                                .background(
                                    model.selectedEpisode == index
                                        ? Color.brand.opacity(0.08)
                                        : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
                .frame(width: 148)
                .background(Color.panel)

                Divider()

                if result.episodes.indices.contains(model.selectedEpisode) {
                    let episode = result.episodes[model.selectedEpisode]
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    localization.text(
                                        "第 {{number}} 集",
                                        ["number": episode.number]
                                    )
                                )
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.brand)
                                Text(episode.title)
                                    .font(.system(size: 16, weight: .bold))
                            }
                            Spacer()
                            Text(localization.text("可直接编辑"))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.secondaryText)
                        }
                        .padding(14)
                        .background(Color.panel)

                        Divider()

                        TextEditor(
                            text: Binding(
                                get: {
                                    guard
                                        let current = model.project.result,
                                        current.episodes.indices.contains(model.selectedEpisode)
                                    else { return "" }
                                    return current.episodes[model.selectedEpisode].content
                                },
                                set: model.updateEpisodeContent
                            )
                        )
                        .font(.system(size: 13, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(16)
                        .background(Color.editorPaper)
                    }
                }
            }
        } else {
            PlaceholderView(
                icon: "text.alignleft",
                title: localization.text("尚未生成剧本"),
                detail: localization.text("完成改编后，可在这里逐集编辑、校对和导出。")
            )
        }
    }
}

private struct QualityReportView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        if let report = model.project.result?.quality {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(localization.text("交付质量"))
                                .font(.system(size: 19, weight: .bold))
                            Text(
                                localization.text(
                                    report.passed
                                        ? "达到初稿交付线"
                                        : "需要修复后再交付"
                                )
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondaryText)
                        }
                        Spacer()
                        Text("\(report.score)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(report.passed ? Color.green : Color.orange)
                    }
                    .padding(18)
                    .background(Color.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    ForEach(report.metrics) { metric in
                        HStack(spacing: 14) {
                            Image(systemName: metricIcon(metric.level))
                                .foregroundStyle(metricColor(metric.level))
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(localization.text(metric.label))
                                    .font(.system(size: 12, weight: .bold))
                                Text(metric.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.secondaryText)
                            }
                            Spacer()
                            Text("\(metric.score)")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(metricColor(metric.level))
                        }
                        .padding(14)
                        .background(Color.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.border, lineWidth: 1)
                        )
                    }

                    if !report.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(localization.text("待处理项"), systemImage: "exclamationmark.triangle")
                                .font(.system(size: 12, weight: .bold))
                            ForEach(report.warnings, id: \.self) { warning in
                                Text("• \(warning)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.secondaryText)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(18)
            }
        } else {
            PlaceholderView(
                icon: "checkmark.shield",
                title: localization.text("等待质量校验"),
                detail: localization.text("生成完成后会自动检查改名、结构、钩子、对白与内容风险。")
            )
        }
    }

    private func metricIcon(_ level: QualityLevel) -> String {
        switch level {
        case .good: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .bad: return "xmark.circle.fill"
        }
    }

    private func metricColor(_ level: QualityLevel) -> Color {
        switch level {
        case .good: return .green
        case .warning: return .orange
        case .bad: return .red
        }
    }
}

private struct CharacterPanelView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(localization.text("人物改名表"))
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text("\(model.project.characters.count)")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.brand.opacity(0.1))
                        .clipShape(Capsule())
                }
                Text(
                    localization.text(
                        "旧名仅用于源文匹配；成稿强制使用新名并检查残留。"
                    )
                )
                .font(.system(size: 9))
                .foregroundStyle(Color.secondaryText)
                .lineSpacing(2)
            }
            .padding(14)

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach($model.project.characters) { $character in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(character.sourceName)
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(
                                        "\(localization.text(character.role)) · \(character.occurrences)"
                                    )
                                    .font(.system(size: 8))
                                    .foregroundStyle(Color.secondaryText)
                                }
                                Spacer()
                                Toggle("", isOn: $character.locked)
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)
                                    .help(localization.text("锁定改名"))
                            }

                            HStack(spacing: 7) {
                                Text(localization.text("剧本新名"))
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Color.secondaryText)
                                TextField("", text: $character.targetName)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 8)
                                    .frame(height: 28)
                                    .background(Color.workspace)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .padding(11)
                        .background(Color.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Color.border, lineWidth: 1)
                        )
                    }
                }
                .padding(10)
            }
        }
        .background(Color.panel)
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore
    @State private var apiKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.text("模型与安全设置"))
                        .font(.system(size: 20, weight: .bold))
                    Label(
                        localization.text("API Key 安全保存在 macOS Keychain"),
                        systemImage: "lock.shield.fill"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondaryText)
                }
                Spacer()
                Picker(localization.text("语言"), selection: $localization.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
            }

            Toggle(
                localization.text("启用在线结构化大模型管线"),
                isOn: $model.modelSettings.useOnline
            )

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("API Base URL")
                TextField("", text: $model.modelSettings.baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("模型")
                TextField("", text: $model.modelSettings.model)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("推理强度")
                Picker("", selection: $model.modelSettings.reasoningEffort) {
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("API Key")
                SecureField(
                    model.hasAPIKey
                        ? localization.text("已保存；留空则保持不变")
                        : "sk-…",
                    text: $apiKey
                )
                .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button(localization.text("取消")) {
                    model.showSettings = false
                }
                .keyboardShortcut(.cancelAction)

                Button(localization.text("保存连接")) {
                    model.saveSettings(apiKey: apiKey)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brand)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func fieldLabel(_ key: String) -> some View {
        Text(localization.text(key))
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.secondaryText)
    }
}

private struct PlaceholderView: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(Color.secondaryText.opacity(0.6))
            Text(title)
                .font(.system(size: 15, weight: .bold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .background(Color.brand.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.primaryText)
            .padding(.horizontal, 13)
            .frame(minHeight: 32)
            .background(configuration.isPressed ? Color.border : Color.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.border, lineWidth: 1)
            )
    }
}

private extension Color {
    static let brand = Color(red: 0.78, green: 0.23, blue: 0.16)
    static let sidebar = Color(red: 0.10, green: 0.11, blue: 0.12)
    static let workspace = Color(red: 0.95, green: 0.94, blue: 0.91)
    static let panel = Color(red: 0.985, green: 0.98, blue: 0.965)
    static let editorPaper = Color(red: 0.99, green: 0.985, blue: 0.97)
    static let border = Color.black.opacity(0.09)
    static let primaryText = Color(red: 0.13, green: 0.14, blue: 0.15)
    static let secondaryText = Color(red: 0.39, green: 0.40, blue: 0.41)
}
