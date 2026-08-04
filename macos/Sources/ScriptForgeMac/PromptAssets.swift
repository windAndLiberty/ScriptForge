import Foundation

enum PromptAssets {
    static let version = "mac-prompts-v2"

    static let defaults: [PromptAsset] = [
        PromptAsset(
            id: "story-evidence",
            title: "故事事实抽取",
            scope: "章节分析、一键拆书证据层",
            influence: "决定模型从原文保留哪些人物、事件、因果和伏笔；不会直接决定剧本文风。",
            instruction: """
            只抽取原文明确支持的事实。每条事实必须保留章节证据 ID；区分已发生事件、人物动机、世界规则和未兑现伏笔，不补写原文没有的信息。
            """,
            isDefault: true,
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        PromptAsset(
            id: "character-naming",
            title: "人物轻量改名",
            scope: "导入后的 Flash 命名调用",
            influence: "影响剧本角色的新名字；用户手动修改的名字优先级最高，后续模型不得擅自更改。",
            instruction: """
            为人物生成符合中国短剧类型和人物气质的自然中文姓名。姓名必须是二至四个汉字，彼此不重复，不得使用“角色8”“男主1”等占位名，不得与原名相同。
            """,
            isDefault: true,
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        PromptAsset(
            id: "story-bible",
            title: "故事圣经与连续性",
            scope: "全剧事实圣经、人物关系、时间线和道具线",
            influence: "约束所有分集的人物身份、关系、能力规则、场景转移和伏笔兑现，是连续性判断的唯一事实源。",
            instruction: """
            将章节证据整理成可执行故事圣经。统一人物身份与别名，明确世界规则的原因和限制，建立按因果排序的时间线；无法由证据支持的内容不得写成确定事实。
            """,
            isDefault: true,
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        PromptAsset(
            id: "episode-planning",
            title: "中国竖屏短剧分集",
            scope: "全局分集契约与单集场次建议",
            influence: "决定每集推进的新事件、开场钩子、反转、结尾卡点和动态场次数，不直接撰写完整对白。",
            instruction: """
            每集只推进一个核心冲突，但必须增加新信息或造成新后果。前 5 秒出现可见冲突，最后 5–8 秒留下未完成动作或信息差。前三集必须快速完成处境、羞辱或危机、能力或真相反转，禁止连续多集重复同一冲突。场次数由剧情决定，60 秒通常 1–3 场。
            """,
            isDefault: true,
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        PromptAsset(
            id: "episode-drafting",
            title: "单集可拍成稿",
            scope: "逐集场景动作和对白",
            influence: "直接影响最终剧本的节奏、动作、对白密度和结尾卡点。",
            instruction: """
            输出中国市场竖屏微短剧成稿。动作必须可见、可拍、能给演员反应抓手；台词短、带攻守关系，不复述观众刚看到的动作。60 秒整集通常 12–18 句对白，单句尽量不超过 18 个汉字。场次不能为凑数拆分，结尾必须停在行动、发现或选择发生的瞬间。
            """,
            isDefault: true,
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        PromptAsset(
            id: "quality-gate",
            title: "可信终审与修复",
            scope: "单集初审、跨集审片、问题台账和定向修复",
            influence: "只决定成稿能否通过以及需要修复的位置；不得为了提高分数重写无问题内容。",
            instruction: """
            以证据为基础检查原著忠实度、人物连续性、动机、时间地点转场、冲突推进、开尾钩子和可拍性。只报告可定位的问题；修复时只处理 blocker 和 major，保留已经有效的场景和台词。
            """,
            isDefault: true,
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        PromptAsset(
            id: "book-analysis",
            title: "一键拆书六模块",
            scope: "结构、人物、爽点、文风、技法和仿写建议",
            influence: "决定拆书报告的深度与证据标准，不会直接修改短剧成稿。",
            instruction: """
            拆书报告必须覆盖内容概览、结构节奏、人物系统、商业爽点、语言文风、可复用技法六个模块。判断必须引用章节证据 ID；明确区分原文事实、分析推论和仿写建议。
            """,
            isDefault: true,
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
    ]

    static func mergedInstruction(_ ids: [String], assets: [PromptAsset]) -> String {
        ids.compactMap { id in assets.first(where: { $0.id == id })?.instruction }
            .joined(separator: "\n\n")
    }

    static func reset(asset: PromptAsset) -> PromptAsset {
        defaults.first(where: { $0.id == asset.id }) ?? asset
    }
}

final class PromptAssetRepository {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL? = nil) {
        let root = baseURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("ScriptForge", isDirectory: true)
        fileURL = root.appendingPathComponent("prompt-assets.json")
        encoder = JSONEncoder.scriptForge
        decoder = JSONDecoder.scriptForge
    }

    func load() -> [PromptAsset] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let saved = try? decoder.decode([PromptAsset].self, from: data)
        else { return PromptAssets.defaults }
        return PromptAssets.defaults.map { defaultAsset in
            saved.first(where: { $0.id == defaultAsset.id }) ?? defaultAsset
        }
    }

    func save(_ assets: [PromptAsset]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(assets).write(to: fileURL, options: .atomic)
    }
}

extension JSONEncoder {
    static var scriptForge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension JSONDecoder {
    static var scriptForge: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
