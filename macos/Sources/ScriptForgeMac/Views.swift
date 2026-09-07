import AppKit
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore
    @Environment(\.interfaceScale) private var interfaceScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var auraPointerLocation = CGPoint.zero
    @State private var isFileDropTargeted = false

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                AuraBackground(pointerLocation: auraPointerLocation)

                HStack(spacing: 0) {
                    SidebarView()
                        .frame(width: InterfaceScalePolicy.layoutScaled(238, by: interfaceScale))
                    Divider()
                        .overlay(Color.border)
                    VStack(spacing: 0) {
                        HeaderView()
                        Divider().overlay(Color.border)
                        content
                    }
                    .background(Color.workspace)
                }

                if let toast = model.toast {
                    Text(toast.text(for: localization.language))
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background {
                            ZStack {
                                Capsule().fill(.regularMaterial)
                                Capsule().fill(Color.black.opacity(0.46))
                            }
                        }
                        .padding(.top, 14)
                        .shadow(color: Color.auraViolet.opacity(0.24), radius: 18, y: 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if isFileDropTargeted {
                    DocumentDropOverlay(route: dropRoute)
                        .environmentObject(localization)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                        .allowsHitTesting(false)
                }
            }
            .onContinuousHover { phase in
                if case let .active(location) = phase {
                    auraPointerLocation = location
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            isFileDropTargeted = false
            return model.importDroppedFiles(urls, route: dropRoute)
        } isTargeted: { targeted in
            isFileDropTargeted = targeted
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
            localization.text("移交到改编工坊"),
            isPresented: $model.pendingCreativeHandoff
        ) {
            Button(localization.text("取消"), role: .cancel) { model.pendingCreativeHandoff = false }
            Button(localization.text("创建快照并移交")) { model.confirmCreativeHandoff() }
        } message: {
            Text(localization.text("将全部已接受章节编译为不可变快照；现有改编和分镜结果会失效，创作版本仍可恢复。"))
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.toast)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isFileDropTargeted)
    }

    private var dropRoute: DocumentImportRoute {
        model.primaryView == .creation ? .creation : .adaptation
    }

    @ViewBuilder
    private var content: some View {
        switch model.primaryView {
        case .bookAnalysis:
            BookAnalysisView()
        case .creation:
            CreativeWorkspaceView()
        case .studio:
            StudioView()
        case .projects:
            ProjectArchiveView()
        case .prompts:
            PromptAssetsView()
        }
    }
}

private struct DocumentDropOverlay: View {
    @EnvironmentObject private var localization: LocalizationStore
    let route: DocumentImportRoute

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.auraBlue, Color.auraViolet, Color.auraCoral],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 2, dash: [10, 7])
                        )
                }
                .padding(26)

            VStack(spacing: 13) {
                Image(systemName: "arrow.down.doc.fill")
                    .scaledFont(size: 44, weight: .medium)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.auraBlue, Color.auraViolet],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(localization.text(
                    route == .creation
                        ? "松开以导入到创作工坊"
                        : "松开以导入到改编工坊"
                ))
                .scaledFont(size: 22, weight: .bold)
                Text(localization.text(
                    "支持 {{formats}}；一次导入一个文件",
                    ["formats": DocumentImporter.supportedFormatNames.joined(separator: " · ")]
                ))
                    .scaledFont(size: 12, weight: .medium)
                    .foregroundStyle(Color.secondaryText)
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
            .auraSurface(.elevated, cornerRadius: 22)
            .shadow(color: Color.auraViolet.opacity(0.25), radius: 28, y: 12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(localization.text("拖拽导入"))
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore
    @Environment(\.interfaceScale) private var interfaceScale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: brandIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: scaled(38), height: scaled(38))
                .shadow(color: Color.auraViolet.opacity(0.34), radius: 12, y: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(localization.text("剧擎"))
                        .scaledFont(size: 17, weight: .bold)
                    Text("SCRIPT FORGE")
                        .scaledFont(size: 8, weight: .bold)
                        .tracking(1.4)
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)

            VStack(spacing: 5) {
                nav(.bookAnalysis, "一键拆书", "wand.and.stars")
                nav(.creation, "创作工坊", "pencil.and.scribble")
                nav(.studio, "改编工坊", "hammer.fill")
                nav(.projects, "项目档案", "archivebox.fill")
                nav(.prompts, "提示词资产", "text.quote")
            }
            .padding(.horizontal, 10)

            Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 16)

            Text(localization.text("当前项目"))
                .scaledFont(size: 10, weight: .bold)
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.42))
                .padding(.horizontal, 18)

            Button {
                if model.project.creativeWorkspace != nil && model.project.document == nil {
                    model.openCreationWorkspace()
                } else {
                    model.primaryView = .studio
                }
            } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.brand.opacity(0.22))
                        .overlay(Image(systemName: "doc.text.fill").foregroundStyle(Color.brandLight))
                        .frame(width: scaled(38), height: scaled(48))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentProjectTitle)
                            .scaledFont(size: 12, weight: .semibold)
                            .lineLimit(2)
                        Text(currentProjectSubtitle)
                            .scaledFont(size: 10)
                            .foregroundStyle(Color.white.opacity(0.48))
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Color.white.opacity(
                    [.studio, .creation].contains(model.primaryView) ? 0.09 : 0.04
                ))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(AuraPlainButtonStyle())
            .padding(10)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Label(localization.text("本地优先"), systemImage: "lock.fill")
                    .scaledFont(size: 11, weight: .semibold)
                Text(localization.text("数据保存在此 Mac"))
                    .scaledFont(size: 10)
                    .foregroundStyle(Color.white.opacity(0.48))
            }
            .padding(18)
        }
        .foregroundStyle(.white)
        .background {
            AuraSurface(level: .sidebar)
        }
    }

    private func nav(_ view: PrimaryView, _ title: String, _ icon: String) -> some View {
        Button {
            model.primaryView = view
        } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).frame(width: scaled(20))
                Text(localization.text(title)).scaledFont(size: 13, weight: .semibold)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: scaled(38))
            .foregroundStyle(model.primaryView == view ? .white : Color.white.opacity(0.62))
            .background {
                if model.primaryView == view {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.auraViolet.opacity(0.92), Color.brand.opacity(0.88)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .shadow(color: Color.auraViolet.opacity(0.2), radius: 12, y: 4)
                } else {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.001))
                }
            }
            .overlay(alignment: .leading) {
                if model.primaryView == view {
                    Capsule()
                        .fill(Color.white.opacity(0.88))
                        .frame(width: scaled(3), height: scaled(18))
                        .offset(x: 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(AuraPlainButtonStyle())
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        InterfaceScalePolicy.scaled(value, by: interfaceScale)
    }

    private var brandIcon: NSImage {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "ScriptForgeAura", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        #else
        if let image = NSImage(named: "ScriptForgeAura") {
            return image
        }
        #endif
        return NSApplication.shared.applicationIconImage
    }

    private var currentProjectTitle: String {
        if model.project.creativeWorkspace != nil {
            return localization.projectName(model.project.name)
        }
        return model.project.document?.title ?? localization.text("尚未导入")
    }

    private var currentProjectSubtitle: String {
        if let creative = model.project.creativeWorkspace {
            return "\(creative.chapters.count) \(localization.countedUnit("章节", count: creative.chapters.count)) · \(localization.text("创作工坊"))"
        }
        guard model.project.document != nil else {
            return localization.text("导入故事或剧本")
        }
        return "\(model.project.chapterCount) \(localization.countedUnit("章节", count: model.project.chapterCount)) · "
            + "\(model.project.generatedEpisodeCount) \(localization.countedUnit("分集", count: model.project.generatedEpisodeCount))"
    }
}

private struct HeaderView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore
    @Environment(\.interfaceScale) private var interfaceScale
    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.system.rawValue

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(localization.text(sectionTitle))
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(Color.secondaryText)
                if model.project.hasContent && (model.primaryView == .studio || model.primaryView == .creation) {
                    TextField(
                        "",
                        text: Binding(
                            get: { localization.projectName(model.project.name) },
                            set: model.updateProjectName
                        )
                    )
                    .textFieldStyle(.plain)
                    .scaledFont(size: 18, weight: .bold)
                    .scaledFrame(maxWidth: 460)
                } else {
                    Text(localization.text(pageName))
                        .scaledFont(size: 18, weight: .bold)
                }
            }
            Spacer()
            if model.project.result != nil && model.primaryView == .studio {
                Button(localization.text("导出成稿")) { model.exportScript() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            Menu {
                ForEach(AppAppearance.allCases) { appearance in
                    Button {
                        appearanceRawValue = appearance.rawValue
                    } label: {
                        Label(
                            localization.text(appearance.titleKey),
                            systemImage: currentAppearance == appearance ? "checkmark" : appearance.symbol
                        )
                    }
                }
            } label: {
                Image(systemName: currentAppearance.symbol)
                    .foregroundStyle(Color.primaryText)
                    .frame(width: scaled(32), height: scaled(32))
                    .auraSurface(.panel, cornerRadius: 9)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .pointingHandCursor()
            .help(localization.text("主题") + " · " + localization.text(currentAppearance.titleKey))
            .accessibilityLabel(localization.text("主题"))
            .accessibilityValue(localization.text(currentAppearance.titleKey))
            Picker("", selection: $localization.language) {
                ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: scaled(104))
            .accessibilityLabel(localization.text("界面语言"))
            Button { model.showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(IconButtonStyle())
            .accessibilityLabel(localization.text("模型设置"))
            Button(localization.text("重置")) { model.resetToHome() }
                .buttonStyle(SecondaryButtonStyle())
                .help(localization.text("重置") + " → Home")
        }
        .padding(.horizontal, 22)
        .frame(minHeight: scaled(66))
        .background {
            AuraSurface(level: .header)
        }
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        InterfaceScalePolicy.scaled(value, by: interfaceScale)
    }

    private var currentAppearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    private var sectionTitle: String {
        switch model.primaryView {
        case .bookAnalysis: "创作系统 / 拆书分析"
        case .creation: "创作系统 / 作者工作流"
        case .studio: "创作系统 / 短剧改编"
        case .projects: "本地工作区 / 项目"
        case .prompts: "创作系统 / 提示词"
        }
    }

    private var pageName: String {
        switch model.primaryView {
        case .bookAnalysis: "一键拆书"
        case .creation: "创作工坊"
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
                    .scaledFrame(width: 340)
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
                        case .storyboard: StoryboardView()
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
                Circle().fill(Color.brand.opacity(0.1)).scaledFrame(width: 114, height: 114)
                Image(systemName: "book.pages.fill")
                    .scaledFont(size: 48)
                    .foregroundStyle(Color.brand)
            }
            Text(localization.text("从故事到已有剧本，锻造成能拍的短剧。"))
                .scaledFont(size: 30, weight: .bold)
            Text(localization.text("自动识别小说或剧本；已有剧本保留集场结构，直接进入分镜。"))
                .scaledFont(size: 14)
                .foregroundStyle(Color.secondaryText)
            Button {
                model.chooseNovel()
            } label: {
                Label(localization.text("导入故事或剧本"), systemImage: "square.and.arrow.down")
                    .padding(.horizontal, 24)
                    .scaledFrame(height: 42)
            }
            .buttonStyle(PrimaryButtonStyle())
            VStack(spacing: 5) {
                Text(localization.text(
                    "本地支持 {{formats}}",
                    ["formats": DocumentImporter.supportedFormatNames.joined(separator: " · ")]
                ))
                Label(
                    localization.text("也可以将文件拖到窗口任意位置"),
                    systemImage: "arrow.down.doc"
                )
            }
            .scaledFont(size: 11)
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
                inspectorSection(localization.text(
                    model.project.sourceKind == .screenplay ? "剧本分集" : "原著章节"
                )) {
                    if let document = model.project.document {
                        HStack {
                            Label(
                                localization.text(document.resolvedSourceKind.chineseLabel),
                                systemImage: document.resolvedSourceKind == .screenplay
                                    ? "film.stack"
                                    : "book.pages"
                            )
                            .scaledFont(size: 10, weight: .semibold)
                            .foregroundStyle(Color.brand)
                            Spacer()
                        }
                        HStack {
                            metric(
                                "\(document.chapters.count)",
                                localization.countedUnit(
                                    document.resolvedSourceKind == .screenplay ? "集" : "章",
                                    count: document.chapters.count
                                )
                            )
                            metric("\(document.characterCount)", localization.text("有效字符"))
                        }
                        Picker("", selection: $model.selectedChapter) {
                            ForEach(Array(document.chapters.enumerated()), id: \.offset) { index, chapter in
                                Text("\(chapter.index). \(localization.documentUnitTitle(chapter.title))").tag(index)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        if document.chapters.indices.contains(model.selectedChapter) {
                            Text(document.chapters[model.selectedChapter].content)
                                .scaledFont(size: 11)
                                .foregroundStyle(Color.secondaryText)
                                .lineLimit(8)
                                .padding(10)
                                .background(Color.workspace)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        if !document.sourceDiagnostics.isEmpty {
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(document.sourceDiagnostics) { diagnostic in
                                    Label {
                                        Text(localization.text(diagnostic))
                                            .scaledFont(size: 10)
                                    } icon: {
                                        Image(systemName: diagnostic.severity == .error
                                            ? "xmark.octagon.fill"
                                            : diagnostic.severity == .warning
                                                ? "exclamationmark.triangle.fill"
                                                : "info.circle.fill")
                                    }
                                    .foregroundStyle(diagnostic.severity == .error
                                        ? Color.red
                                        : diagnostic.severity == .warning ? Color.orange : Color.secondaryText)
                                }
                            }
                        }
                    }
                }

                inspectorSection(localization.text(
                    model.project.sourceKind == .screenplay ? "原稿人物" : "人物新名"
                )) {
                    if model.isNaming {
                        Label(localization.text("人物命名中…"), systemImage: "sparkles")
                            .foregroundStyle(Color.brand)
                    }
                    ForEach(model.project.characters) { character in
                        VStack(alignment: .leading, spacing: 5) {
                            if model.project.sourceKind == .screenplay {
                                Label(character.sourceName, systemImage: "person.crop.circle")
                                    .scaledFont(size: 11, weight: .semibold)
                            } else {
                                HStack {
                                    Text(character.sourceName)
                                        .scaledFont(size: 11)
                                        .foregroundStyle(Color.secondaryText)
                                    Image(systemName: "arrow.right").scaledFont(size: 9)
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
                            }
                            Text(localization.text(character.role) + " · " + characterNameSourceLabel(character.nameSource))
                                .scaledFont(size: 9)
                                .foregroundStyle(Color.secondaryText)
                        }
                    }
                }

                inspectorSection(localization.text("改编规格")) {
                    if model.project.sourceKind == .screenplay {
                        specRow(localization.text("原稿集数"), "\(model.project.options.episodeCount)")
                        Text(localization.text("已有剧本不会被二次改编；集、场、对白和钩子按原稿保留。"))
                            .scaledFont(size: 10)
                            .foregroundStyle(Color.secondaryText)
                    } else {
                        Stepper(
                            value: Binding(
                                get: { model.project.options.episodeCount },
                                set: { value in model.updateOptions { $0.episodeCount = value } }
                            ),
                            in: 1...100
                        ) {
                            specRow(localization.text("目标集数"), "\(model.project.options.episodeCount)")
                        }
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
                    Text(localization.text(model.project.sourceKind == .screenplay
                        ? "场次数与内容来自原稿结构"
                        : "场次数由模型动态决定"))
                        .scaledFont(size: 10, weight: .semibold)
                        .foregroundStyle(Color.brand)
                    TextField(
                        localization.text("题材"),
                        text: Binding(
                            get: { model.project.options.resolvedGenre(for: localization.language) },
                            set: { value in model.updateOptions { $0.genre = value } }
                        )
                    )
                    TextField(
                        localization.text("基调"),
                        text: Binding(
                            get: { model.project.options.resolvedTone(for: localization.language) },
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
                            Text(localization.text(model.project.sourceKind == .screenplay
                                ? "重新解析原稿"
                                : model.project.result == nil ? "开始改编" : "重新生成"))
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .padding(.horizontal, 14)
                        .scaledFrame(height: 42)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isRunning || model.isNaming)

                    if model.isRunning {
                        Button(localization.text("取消任务")) { model.cancelCurrentTask() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Label(
                        localization.text(model.project.sourceKind == .screenplay
                            ? "本地剧本直通"
                            : model.modelReady ? "双模型可信管线" : "本地基础管线"),
                        systemImage: model.project.sourceKind == .screenplay
                            ? "film.stack"
                            : model.modelReady ? "bolt.shield.fill" : "laptopcomputer"
                    )
                    .scaledFont(size: 10, weight: .semibold)
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
                .scaledFont(size: 10, weight: .bold)
                .tracking(1)
                .foregroundStyle(Color.secondaryText)
            content()
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).scaledFont(size: 18, weight: .bold)
            Text(label).scaledFont(size: 9).foregroundStyle(Color.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func specRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).fontWeight(.bold) }
    }

    private func characterNameSourceLabel(_ source: CharacterNameSource) -> String {
        switch source {
        case .local: localization.text("本地生成")
        case .model: localization.text("模型生成")
        case .manual: localization.text("手动编辑")
        }
    }
}

private struct PipelineProgressView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(model.pipelineProgress.detail.isEmpty
                    ? localization.text("管线就绪")
                    : model.pipelineProgress.detail)
                    .scaledFont(size: 11, weight: .semibold)
                Spacer()
                Text("\(Int(model.pipelineProgress.fraction * 100))%")
                    .scaledFont(size: 11, weight: .bold)
            }
            ProgressView(value: model.pipelineProgress.fraction)
                .tint(Color.brand)
        }
        .padding(.horizontal, 18)
        .scaledFrame(height: 58)
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
            tab(.storyboard, "分镜制作", "rectangle.split.3x1")
            tab(.quality, "质检报告", "checkmark.shield")
            Spacer()
        }
        .padding(.horizontal, 16)
        .scaledFrame(height: 46)
        .background(Color.panel)
    }

    private func tab(_ value: StudioTab, _ title: String, _ icon: String) -> some View {
        Button {
            model.activeTab = value
        } label: {
            Label(localization.text(title), systemImage: icon)
                .scaledFont(size: 11, weight: .semibold)
                .padding(.horizontal, 11)
                .scaledFrame(height: 30)
                .foregroundStyle(model.activeTab == value ? Color.brand : Color.secondaryText)
                .background(model.activeTab == value ? Color.brand.opacity(0.09) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(AuraPlainButtonStyle())
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
                                    .scaledFont(size: 10, weight: .bold)
                                    .foregroundStyle(Color.brand)
                                Text(localization.language == .english ? episode.title : "《\(episode.title)》")
                                    .scaledFont(size: 16, weight: .bold)
                                Spacer()
                                Label(
                                    "\(episode.scenes.count) " + localization.text("动态场次"),
                                    systemImage: "camera.fill"
                                )
                                .scaledFont(size: 10)
                                .foregroundStyle(Color.secondaryText)
                            }
                            HStack(alignment: .top, spacing: 10) {
                                contractCell("冷开场", episode.openingHook)
                                contractCell("本集目标", episode.objective)
                                contractCell("中段反转", episode.reversal)
                                contractCell("结尾卡点", episode.endHook)
                            }
                            Text(episode.contract.transitionFromPrevious)
                                .scaledFont(size: 10)
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
            Text(localization.text(label)).scaledFont(size: 9, weight: .bold).foregroundStyle(Color.brand)
            Text(value).scaledFont(size: 11).lineLimit(4)
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
                    Text(bible.premise).scaledFont(size: 16, weight: .semibold).panelCard()
                    bibleSection(localization.text("人物")) {
                        ForEach(bible.canonicalCharacters) { character in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(character.scriptName).fontWeight(.bold)
                                Text(character.role + " · " + character.relationships.joined(
                                    separator: localization.language == .english ? "; " : "；"
                                ))
                                    .scaledFont(size: 11).foregroundStyle(Color.secondaryText)
                            }
                        }
                    }
                    bibleSection(localization.text("世界规则")) {
                        ForEach(bible.worldRules) { rule in
                            Text(localization.language == .english
                                ? "• \(rule.subject): \(rule.fact) (\(rule.cause))"
                                : "• \(rule.subject)：\(rule.fact)（\(rule.cause)）")
                                .scaledFont(size: 11)
                        }
                    }
                    bibleSection(localization.text("时间线")) {
                        ForEach(bible.timeline) { event in
                            Text("\(event.order). \(event.event) → \(event.effect)").scaledFont(size: 11)
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
            Text(title).scaledFont(size: 13, weight: .bold).foregroundStyle(Color.brand)
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
                                Text("\(episode.scenes.count) \(localization.text("场")) · \(episode.runtime?.estimatedSeconds ?? 0, specifier: "%.1f")s")
                                    .scaledFont(size: 9).foregroundStyle(Color.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .background(model.selectedEpisode == index ? Color.brand.opacity(0.08) : Color.clear)
                        }
                        .buttonStyle(AuraPlainButtonStyle())
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .scaledFrame(width: 220)
                Divider()
                if result.episodes.indices.contains(model.selectedEpisode) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("EP \(result.episodes[model.selectedEpisode].number)")
                                .scaledFont(size: 11, weight: .bold).foregroundStyle(Color.brand)
                            Spacer()
                            Text(localization.text("剧本编辑"))
                                .scaledFont(size: 10).foregroundStyle(Color.secondaryText)
                        }
                        .padding(.horizontal, 18)
                        .scaledFrame(height: 42)
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
                        .auraTextEditor()
                        .scaledFont(size: 14, design: .monospaced)
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

private struct StoryboardView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localization.text("分镜制作包"))
                        .scaledFont(size: 15, weight: .bold)
                    Text(localization.text("从已批准剧本生成镜头、首帧提示词、声音和连续性标注"))
                        .scaledFont(size: 10)
                        .foregroundStyle(Color.secondaryText)
                }
                Spacer()
                if model.project.productionPackage != nil {
                    Button(localization.text("导出分镜")) { model.exportStoryboards() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Button {
                    model.generateStoryboards()
                } label: {
                    Label(
                        localization.text(model.project.productionPackage == nil ? "生成分镜" : "重新生成分镜"),
                        systemImage: "wand.and.stars"
                    )
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isRunning || model.isProducing)
            }
            .padding(.horizontal, 18)
            .scaledFrame(minHeight: 58)
            .background(Color.panel)

            if model.isProducing || model.storyboardProgress.fraction > 0 {
                HStack(spacing: 12) {
                    ProgressView(value: model.storyboardProgress.fraction).tint(Color.brand)
                    Text(model.storyboardProgress.detail)
                        .scaledFont(size: 10, weight: .medium)
                        .foregroundStyle(Color.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .scaledFrame(height: 34)
                .background(Color.panel)
            }
            Divider()

            if let package = model.project.productionPackage, !package.episodes.isEmpty {
                storyboardWorkspace(package)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "rectangle.split.3x1")
                        .scaledFont(size: 42)
                        .foregroundStyle(Color.brand.opacity(0.75))
                    Text(localization.text("尚未生成分镜"))
                        .scaledFont(size: 15, weight: .semibold)
                    Text(localization.text("离线模式也可生成完整文本分镜；图片与配音按需使用 BYOK 模型。"))
                        .scaledFont(size: 11)
                        .foregroundStyle(Color.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func storyboardWorkspace(_ package: ProductionPackage) -> some View {
        HStack(spacing: 0) {
            List {
                ForEach(Array(package.episodes.enumerated()), id: \.offset) { index, episode in
                    Button {
                        model.selectedEpisode = index
                        model.selectedShot = 0
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("EP \(episode.episodeNumber) · \(episode.title)")
                                .fontWeight(.semibold)
                            Text("\(episode.shots.count) shots · \(episode.totalDurationSeconds, specifier: "%.1f")s")
                                .scaledFont(size: 9)
                                .foregroundStyle(Color.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(AuraPlainButtonStyle())
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .scaledFrame(width: 190)
            Divider()

            if package.episodes.indices.contains(model.selectedEpisode) {
                let episode = package.episodes[model.selectedEpisode]
                HStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(episode.shots.enumerated()), id: \.offset) { index, shot in
                                Button {
                                    model.selectedShot = index
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack {
                                            Text(String(format: "%02d", shot.number))
                                                .scaledFont(size: 9, weight: .bold)
                                                .foregroundStyle(Color.brand)
                                            Text(shot.title).scaledFont(size: 11, weight: .semibold)
                                            Spacer()
                                            Text("\(shot.durationSeconds, specifier: "%.1f")s")
                                                .scaledFont(size: 9)
                                        }
                                        Text("\(shot.shotSize) · \(shot.cameraMovement)")
                                            .scaledFont(size: 9)
                                            .foregroundStyle(Color.secondaryText)
                                        HStack(spacing: 5) {
                                            if shot.keyframePath != nil { Image(systemName: "photo.fill") }
                                            if shot.narrationPath != nil { Image(systemName: "waveform") }
                                        }
                                        .scaledFont(size: 9)
                                        .foregroundStyle(Color.brand)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(model.selectedShot == index ? Color.brand.opacity(0.10) : Color.panel)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.border))
                                }
                                .buttonStyle(AuraPlainButtonStyle())
                            }
                        }
                        .padding(12)
                    }
                    .scaledFrame(width: 250)
                    Divider()

                    if episode.shots.indices.contains(model.selectedShot) {
                        shotDetail(episode.shots[model.selectedShot], episodeIndex: model.selectedEpisode, shotIndex: model.selectedShot)
                    }
                }
            }
        }
    }

    private func shotDetail(_ shot: StoryboardShot, episodeIndex: Int, shotIndex: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SHOT \(String(format: "%02d", shot.number))")
                            .scaledFont(size: 10, weight: .bold)
                            .foregroundStyle(Color.brand)
                        Text(shot.title).scaledFont(size: 21, weight: .bold)
                    }
                    Spacer()
                    Text("\(shot.shotSize) · \(shot.cameraMovement) · \(shot.durationSeconds, specifier: "%.1f")s")
                        .scaledFont(size: 10, weight: .semibold)
                        .foregroundStyle(Color.secondaryText)
                }

                keyframe(shot)

                HStack(spacing: 8) {
                    Button {
                        model.generateKeyframe(episodeIndex: episodeIndex, shotIndex: shotIndex)
                    } label: {
                        Label(localization.text(shot.keyframePath == nil ? "生成首帧" : "重新生成首帧"), systemImage: "photo.badge.plus")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.isProducing || !model.modelReady || model.modelSettings.imageModel.isEmpty)

                    Button {
                        model.generateNarration(episodeIndex: episodeIndex, shotIndex: shotIndex)
                    } label: {
                        Label(localization.text(shot.narrationPath == nil ? "生成配音" : "重新生成配音"), systemImage: "waveform.badge.plus")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.isProducing || !model.modelReady || model.modelSettings.speechModel.isEmpty || (shot.narration.isEmpty && shot.dialogue.isEmpty))

                    if let path = shot.narrationPath {
                        Button {
                            model.playNarration(relativePath: path)
                        } label: {
                            Label(localization.text("播放"), systemImage: "play.fill")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }

                detailSection(localization.text("画面动作"), shot.visualAction)
                if !shot.dialogue.isEmpty { detailSection(localization.text("台词"), shot.dialogue) }
                if !shot.narration.isEmpty { detailSection(localization.text("旁白"), shot.narration) }
                detailSection(localization.text("构图"), shot.composition)
                detailSection(localization.text("声音设计"), shot.soundEffects)
                detailSection(localization.text("连续性"), shot.continuityNotes)
                detailSection(localization.text("制作备注"), shot.productionNotes)
                detailSection(localization.text("首帧提示词"), shot.imagePrompt)
                detailSection(localization.text("反向提示词"), shot.negativePrompt)
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private func keyframe(_ shot: StoryboardShot) -> some View {
        if let path = shot.keyframePath,
           let url = model.mediaURL(relativePath: path),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .scaledFrame(maxWidth: .infinity, minHeight: 220, maxHeight: 410)
                .background(Color.black.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            ZStack {
                Color.black.opacity(0.88)
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait")
                        .scaledFont(size: 34)
                    Text("9:16 · \(localization.text("首帧待生成"))")
                        .scaledFont(size: 11, weight: .semibold)
                }
                .foregroundStyle(.white.opacity(0.75))
            }
            .aspectRatio(9 / 16, contentMode: .fit)
            .scaledFrame(maxHeight: 330)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func detailSection(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).scaledFont(size: 10, weight: .bold).foregroundStyle(Color.brand)
            Text(value).scaledFont(size: 12).textSelection(.enabled)
        }
        .panelCard()
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
                            Text("\(quality.score)").scaledFont(size: 44, weight: .bold)
                            Text(localization.text("综合分")).foregroundStyle(Color.secondaryText)
                        }
                        Divider().scaledFrame(height: 54)
                        Label(
                            localization.text(quality.passed ? "达到交付线" : "需要人工复核"),
                            systemImage: quality.passed ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
                        )
                        .foregroundStyle(quality.passed ? Color.green : Color.orange)
                        Spacer()
                        if let gate = quality.gate {
                            VStack(alignment: .trailing) {
                                Text("\(gate.openIssueCount)").scaledFont(size: 22, weight: .bold)
                                Text(localization.text("开放问题")).scaledFont(size: 10).foregroundStyle(Color.secondaryText)
                            }
                        }
                    }
                    .panelCard()

                    ForEach(quality.metrics) { metric in
                        HStack(spacing: 12) {
                            Circle().fill(metric.level.color).scaledFrame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(metric.label).fontWeight(.semibold)
                                Text(metric.detail).scaledFont(size: 11).foregroundStyle(Color.secondaryText)
                            }
                            Spacer()
                            Text("\(metric.score)").scaledFont(size: 18, weight: .bold)
                        }
                        .panelCard()
                    }

                    if let issues = quality.gate?.issues.filter({ !$0.resolved }), !issues.isEmpty {
                        Text(localization.text("开放问题")).scaledFont(size: 16, weight: .bold)
                        ForEach(issues) { issue in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(issueSeverityLabel(issue.severity).uppercased())
                                        .scaledFont(size: 9, weight: .bold)
                                        .foregroundStyle(issue.severity == .blocker ? Color.red : Color.orange)
                                    Text("EP " + issue.episodeNumbers.map(String.init).joined(separator: ", "))
                                        .scaledFont(size: 10, weight: .semibold)
                                }
                                Text(issue.evidence).scaledFont(size: 12)
                                Text("→ " + issue.repairInstruction)
                                    .scaledFont(size: 11).foregroundStyle(Color.secondaryText)
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

    private func issueSeverityLabel(_ severity: QualityIssueSeverity) -> String {
        switch severity {
        case .blocker: localization.text("阻断")
        case .major: localization.text("严重")
        case .minor: localization.text("轻微")
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
                                .scaledFont(size: 26, weight: .bold)
                            Text(model.project.document?.title ?? "")
                                .foregroundStyle(Color.secondaryText)
                        }
                        Spacer()
                        if model.project.bookAnalysis != nil {
                            Button(localization.text("导出报告")) {
                                model.exportBookAnalysis(language: localization.language)
                            }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(
                            localization.text("使用原文语言"),
                            isOn: Binding(
                                get: { model.project.options.preserveSourceLanguage },
                                set: { value in
                                    model.updateOptions { $0.preserveSourceLanguage = value }
                                }
                            )
                        )
                        .toggleStyle(.switch)

                        Text(localization.text("默认保持原稿的主要语言，避免分析与分集中英文混杂。"))
                            .scaledFont(size: 11)
                            .foregroundStyle(Color.secondaryText)

                        if model.project.options.preserveSourceLanguage {
                            HStack {
                                Text(localization.text("已检测原文语言"))
                                Spacer()
                                Text(model.resolvedContentLanguage.label)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.brand)
                            }
                            .scaledFont(size: 11)
                        } else {
                            Picker(
                                localization.text("指定输出语言"),
                                selection: Binding(
                                    get: { model.project.options.targetLanguage },
                                    set: { value in
                                        model.updateOptions { $0.targetLanguage = value }
                                    }
                                )
                            ) {
                                ForEach(AppLanguage.allCases) { language in
                                    Text(language.label).tag(language)
                                }
                            }
                        }
                    }
                    .panelCard()

                    HStack {
                        Spacer()
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
                            .scaledFont(size: 11, weight: .semibold)
                            ProgressView(value: model.bookProgress.fraction).tint(Color.brand)
                        }
                        .panelCard()
                    }

                    if let report = model.project.bookAnalysis {
                        HStack(spacing: 12) {
                            metricCard(localization.text("证据覆盖"), "\(report.coveragePercent)%")
                            metricCard(
                                localization.text("模式"),
                                localization.text(report.mode == .online ? "在线" : "离线").uppercased()
                            )
                            metricCard(localization.text("版本"), "\(model.project.bookAnalysisVersions.count)/8")
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(report.logline).scaledFont(size: 16, weight: .semibold)
                            Text(report.summary).scaledFont(size: 12).foregroundStyle(Color.secondaryText)
                            Text(report.genreTags.joined(separator: " · "))
                                .scaledFont(size: 10, weight: .semibold).foregroundStyle(Color.brand)
                        }
                        .panelCard()
                        ForEach(report.sections) { section in
                            VStack(alignment: .leading, spacing: 9) {
                                Text(section.title).scaledFont(size: 17, weight: .bold)
                                Text(section.markdown).scaledFont(size: 12).textSelection(.enabled)
                                Text((report.outputLanguage ?? .chinese) == .english
                                    ? "Evidence: " + section.evidenceChapterIDs.joined(separator: " · ")
                                    : "证据：" + section.evidenceChapterIDs.joined(separator: " · "))
                                    .scaledFont(size: 9).foregroundStyle(Color.secondaryText)
                            }
                            .panelCard()
                        }
                        VStack(alignment: .leading, spacing: 9) {
                            Text(localization.text("修订指令")).fontWeight(.bold)
                            TextEditor(text: $revisionInstruction)
                                .auraTextEditor()
                                .scaledFrame(minHeight: 74)
                                .padding(8)
                                .background(Color.workspace)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            Button(localization.text("提交微调")) {
                                model.reviseBookAnalysis(
                                    instruction: revisionInstruction,
                                    language: localization.language
                                )
                                revisionInstruction = ""
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(!model.modelReady || revisionInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .panelCard()
                    } else {
                        EmptyState(icon: "wand.and.stars", title: localization.text("准备开始一键拆书"))
                            .scaledFrame(height: 360)
                    }
                }
                .padding(24)
            }
        }
    }

    private func metricCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).scaledFont(size: 22, weight: .bold)
            Text(title).scaledFont(size: 10).foregroundStyle(Color.secondaryText)
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
                        Text(localization.text("项目档案")).scaledFont(size: 27, weight: .bold)
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
                    summaryStatic("\(model.projectLibrary.reduce(0) { $0 + $1.chapterCount })", "累计内容单元")
                    summaryStatic("\(model.projectLibrary.reduce(0) { $0 + $1.generatedEpisodeCount })", "已生成集数")
                }

                let visible = selected == .recent ? model.recentProjects : model.archivedProjects
                if visible.isEmpty {
                    EmptyState(icon: "archivebox", title: localization.text("没有项目"))
                        .scaledFrame(height: 340)
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
        .buttonStyle(AuraPlainButtonStyle())
    }

    private func summaryStatic(_ value: String, _ title: String) -> some View {
        summaryContent(value, title)
            .background(Color.panel)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.border))
    }

    private func summaryContent(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).scaledFont(size: 24, weight: .bold)
            Text(localization.text(title)).scaledFont(size: 10).foregroundStyle(Color.secondaryText)
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
                    .scaledFrame(width: 46, height: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.projectName(project.name)).scaledFont(size: 14, weight: .bold).lineLimit(2)
                    Text(project.document?.title ?? localization.text("尚未导入"))
                        .scaledFont(size: 10).foregroundStyle(Color.secondaryText)
                }
                Spacer()
            }
            HStack {
                Label("\(project.chapterCount)", systemImage: "book.pages")
                Label("\(project.generatedEpisodeCount)", systemImage: "play.rectangle")
                Spacer()
                Text(project.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
            .scaledFont(size: 9).foregroundStyle(Color.secondaryText)
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
                    .accessibilityLabel(localization.text("确认删除"))
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
    @State private var selectedCreativeID = CreativeWorkflowID.incubation
    @State private var mode = "creative"
    @State private var creativeDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                Text(localization.text("创作工作流")).tag("creative")
                Text(localization.text("改编与分镜")).tag("adaptation")
            }
            .pickerStyle(.segmented)
            .scaledFrame(width: 300)
            .padding(12)
            Divider()
            if mode == "creative" { creativeEditor }
            else { adaptationEditor }
        }
    }

    private var adaptationEditor: some View {
        HStack(spacing: 0) {
            List(model.promptAssets, selection: $selectedID) { asset in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(localization.text(asset.title)).fontWeight(.semibold)
                        Image(systemName: "info.circle")
                            .scaledFont(size: 10)
                            .foregroundStyle(Color.secondaryText)
                            .help(localization.text("影响范围")
                                + (localization.language == .english ? ": " : "：")
                                + localization.text(asset.influence))
                    }
                    Text(localization.text(asset.scope)).scaledFont(size: 9).foregroundStyle(Color.secondaryText)
                }
                .tag(asset.id)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .scaledFrame(width: 270)
            Divider()
            if let asset = model.promptAssets.first(where: { selectedID == $0.id }) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(localization.text(asset.title)).scaledFont(size: 22, weight: .bold)
                            Text(localization.text(asset.scope)).foregroundStyle(Color.secondaryText)
                        }
                        Spacer()
                        Button(localization.text("恢复默认")) { model.resetPromptAsset(id: asset.id) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Label(localization.text(asset.influence), systemImage: "info.circle.fill")
                        .scaledFont(size: 11)
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
                    .auraTextEditor()
                    .scaledFont(size: 13, design: .monospaced)
                    .padding(12)
                    .background(Color.editorPaper)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.border))
                }
                .padding(24)
            }
        }
    }

    private var creativeEditor: some View {
        HStack(spacing: 0) {
            List(CreativeWorkflowID.allCases, selection: $selectedCreativeID) { workflowID in
                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.text(workflowID.title)).fontWeight(.semibold)
                    Text(localization.text(CreativeWorkflowRegistry.definition(workflowID).summary))
                        .scaledFont(size: 9)
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(2)
                }
                .tag(workflowID)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .scaledFrame(width: 270)
            Divider()
            if let prompt = model.creativePromptOverrides.first(where: { $0.workflowID == selectedCreativeID }) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(localization.text(selectedCreativeID.title))
                                .scaledFont(size: 22, weight: .bold)
                            Text(localization.text("工作流级提示词；项目规则和本次补充会在运行时追加。"))
                                .foregroundStyle(Color.secondaryText)
                        }
                        Spacer()
                        Button(localization.text("恢复默认")) {
                            model.resetCreativePrompt(selectedCreativeID)
                            creativeDraft = CreativePromptTemplates.defaultInstruction(for: selectedCreativeID)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        Button(localization.text("保存版本")) {
                            model.updateCreativePrompt(selectedCreativeID, instruction: creativeDraft)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    TextEditor(text: $creativeDraft)
                    .auraTextEditor()
                    .scaledFont(size: 13, design: .monospaced)
                    .padding(12)
                    .background(Color.editorPaper)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.border))
                    Text(localization.text("版本历史"))
                        .scaledFont(size: 11, weight: .bold)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(prompt.revisions.reversed()) { revision in
                                Button {
                                    model.restoreCreativePromptRevision(
                                        selectedCreativeID,
                                        revisionID: revision.id
                                    )
                                    creativeDraft = revision.instruction
                                } label: {
                                    Text(revision.createdAt.formatted(date: .numeric, time: .shortened))
                                        .scaledFont(size: 9)
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .onAppear { loadCreativeDraft() }
        .onChange(of: selectedCreativeID) { _, _ in loadCreativeDraft() }
    }

    private func loadCreativeDraft() {
        creativeDraft = model.creativePromptOverrides.first(where: {
            $0.workflowID == selectedCreativeID
        })?.instruction ?? CreativePromptTemplates.defaultInstruction(for: selectedCreativeID)
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.interfaceScale) private var interfaceScaleEnvironment
    @AppStorage(InterfaceScalePolicy.storageKey) private var interfaceScale = InterfaceScalePolicy.defaultValue
    @State private var settings: ModelSettings
    @State private var apiKey = ""
    @State private var consentGranted: Bool

    init() {
        _settings = State(initialValue: ModelSettings())
        _consentGranted = State(initialValue: false)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(localization.text("模型与安全设置"))
                        .scaledFont(size: 21, weight: .bold)
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(IconButtonStyle())
                        .accessibilityLabel(localization.text("取消"))
                }

                accessibilitySection
                Divider().overlay(Color.border)

                Toggle(localization.text("启用在线双模型管线"), isOn: $settings.useOnline)
                settingField("API Base URL") { TextField("https://api.openai.com/v1", text: $settings.baseURL) }
                settingField("创作模型（Pro）") { TextField("gpt-5.6-sol", text: $settings.primaryModel) }
                settingField("高速模型（Flash）") { TextField("gpt-5.6-terra", text: $settings.flashModel) }
                settingField("图片模型（可选）") { TextField(localization.text("例如 gpt-image-1"), text: $settings.imageModel) }
                settingField("语音模型（可选）") { TextField(localization.text("例如 gpt-4o-mini-tts"), text: $settings.speechModel) }
                settingField("配音音色") { TextField("alloy", text: $settings.speechVoice) }
                settingField("推理强度") {
                    Picker("", selection: $settings.reasoningEffort) {
                        ForEach(["none", "low", "medium", "high"], id: \.self) { Text($0).tag($0) }
                    }.labelsHidden()
                }
                settingField("API Key") {
                    SecureField(model.hasAPIKey ? "•••••••• (saved)" : "sk-…", text: $apiKey)
                }
                Toggle(localization.text("同意发送到当前端点"), isOn: $consentGranted)
                Text(localization.text("在线改编与可选多媒体生成只发送到上方域名。图片和语音模型留空即禁用；密钥仅保存在 macOS Keychain。"))
                    .scaledFont(size: 11)
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
        }
        .frame(
            width: min(760, max(540, InterfaceScalePolicy.scaled(590, by: interfaceScaleEnvironment))),
            height: min(760, max(520, InterfaceScalePolicy.scaled(610, by: interfaceScaleEnvironment)))
        )
        .background {
            AuraSurface(level: .elevated)
        }
        .onAppear {
            settings = model.modelSettings
            consentGranted = model.modelSettings.hasEndpointConsent
            interfaceScale = InterfaceScalePolicy.normalized(interfaceScale)
        }
    }

    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localization.text("无障碍访问"))
                .scaledFont(size: 13, weight: .bold)
            HStack(spacing: 10) {
                Button {
                    interfaceScale = InterfaceScalePolicy.decrease(interfaceScale)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(IconButtonStyle())
                .disabled(normalizedInterfaceScale <= InterfaceScalePolicy.minimum)
                .accessibilityLabel(localization.text("缩小"))

                Slider(
                    value: Binding(
                        get: { normalizedInterfaceScale },
                        set: { interfaceScale = InterfaceScalePolicy.normalized($0) }
                    ),
                    in: InterfaceScalePolicy.minimum...InterfaceScalePolicy.maximum,
                    step: InterfaceScalePolicy.step
                )
                .accessibilityLabel(localization.text("界面缩放"))
                .accessibilityValue(InterfaceScalePolicy.percentage(normalizedInterfaceScale))

                Text(InterfaceScalePolicy.percentage(normalizedInterfaceScale))
                    .scaledFont(size: 12, weight: .semibold, design: .monospaced)
                    .frame(minWidth: InterfaceScalePolicy.scaled(48, by: interfaceScaleEnvironment))
                    .accessibilityHidden(true)

                Button {
                    interfaceScale = InterfaceScalePolicy.increase(interfaceScale)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(IconButtonStyle())
                .disabled(normalizedInterfaceScale >= InterfaceScalePolicy.maximum)
                .accessibilityLabel(localization.text("放大"))

                Button(localization.text("实际大小")) {
                    interfaceScale = InterfaceScalePolicy.defaultValue
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(normalizedInterfaceScale == InterfaceScalePolicy.defaultValue)
                .accessibilityLabel(localization.text("重置缩放"))
            }
        }
        .padding(12)
        .auraSurface(.panel, cornerRadius: 10)
    }

    private var normalizedInterfaceScale: Double {
        InterfaceScalePolicy.normalized(interfaceScale)
    }

    private func settingField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(localization.text(title))
                .frame(
                    width: InterfaceScalePolicy.scaled(150, by: interfaceScaleEnvironment),
                    alignment: .leading
                )
            content().textFieldStyle(.roundedBorder)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct EmptyState: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).scaledFont(size: 36).foregroundStyle(Color.brand.opacity(0.7))
            Text(title).scaledFont(size: 14, weight: .semibold).foregroundStyle(Color.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
