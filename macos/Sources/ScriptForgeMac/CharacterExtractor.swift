import Foundation

enum CharacterExtractor {
    private static let surnames = Set(
        "赵钱孙李周吴郑王冯陈褚卫蒋沈韩杨朱秦许何吕施张孔曹严华金魏陶姜谢邹苏潘葛范彭鲁韦昌马苗方任袁柳史唐费廉岑薛雷贺倪汤滕殷罗毕郝安常乐于时傅齐康伍余顾孟平黄穆萧尹姚邵汪毛米贝明成戴宋熊纪舒项祝董梁杜蓝季贾路江童颜郭梅盛林钟徐邱骆高夏蔡田樊胡凌霍虞万卢莫房左石崔吉龚程邢裴陆荣翁段富焦巴牧谷车侯全班秋仲宫宁甘厉祖武刘景龙叶黎乔闻党谭申艾向古易慎廖冷辛曾沙关红游权"
    )
    private static let invalid: Set<String> = [
        "王八蛋", "小姐", "小姐姐", "先生", "老板", "同学", "老师", "医生",
        "护士", "系统", "主角", "对手", "作者", "华夏", "江城", "小爷",
        "老子", "人家", "大力", "颜色", "农夫", "时候", "红砖", "酒瓶",
        "空间系", "力量系", "马上", "于是", "如果", "虽然", "已经",
    ]
    private static let invalidEndings = Set(
        "的了着过是在有和与及也都不没这那你我他她它们啊吗呢吧城国省市县区镇村家中上下后前系级者人天年日时分秒个种样处所事物话声眼手脚头脸心边面里外间校院店路门口队方次点"
    )
    private static let femaleHints = Set("雪瑶妍嫣琳玲萱薇倩婷晴月婉柔静茜颖蕾菲兰言溪晚")
    private static let femaleNames = [
        "沈知夏", "林妍", "苏清禾", "许昭月", "叶晚晴", "温以宁", "乔知意",
        "姜予安", "宋微澜", "顾南枝", "陆清禾", "夏知微",
    ]
    private static let maleNames = [
        "程野", "周骁", "顾川", "陆沉舟", "贺砚", "秦越", "裴峥", "江屿",
        "沈砚", "谢临", "傅言川", "陈既明", "萧景行", "周既白",
    ]
    private static let fallbackNames = [
        "程野", "沈知夏", "顾川", "苏清禾", "陆沉舟", "许昭月", "贺砚",
        "叶晚晴", "秦越", "温以宁", "裴峥", "乔知意", "江屿", "姜予安",
        "沈砚", "宋微澜", "谢临", "顾南枝", "傅言川", "陈既明",
    ]
    private static let genericNamePattern =
        #"^(?:角色|人物|主角|配角|男主|女主|男配|女配|路人|甲|乙|丙|丁)\s*\d*$"#

    struct RenameProposal: Codable, Hashable, Sendable {
        let sourceName: String
        let targetName: String
    }

    static func extract(from document: NovelDocument, limit: Int = 12) -> [CharacterProfile] {
        let text = document.chapters.map(\.content).joined(separator: "\n")
        let characters = Array(text)
        var seeds = Set<String>()
        guard characters.count >= 2 else { return [] }
        for index in 0..<(characters.count - 1) where surnames.contains(characters[index]) {
            seeds.insert(String(characters[index...index + 1]))
            if index + 2 < characters.count {
                seeds.insert(String(characters[index...index + 2]))
            }
        }

        let ranked = seeds.compactMap { name -> (String, Int, Int)? in
            guard plausible(name) else { return nil }
            let count = occurrences(of: name, in: text)
            guard count >= 2 else { return nil }
            return (name, count, count + contextualBoost(name: name, in: text))
        }.sorted {
            if $0.2 == $1.2 { return $0.0.count > $1.0.count }
            return $0.2 > $1.2
        }

        var selected: [(String, Int, Int)] = []
        for candidate in ranked {
            if selected.contains(where: {
                $0.0.contains(candidate.0) || candidate.0.contains($0.0)
            }) { continue }
            selected.append(candidate)
            if selected.count == limit { break }
        }

        var femaleIndex = 0
        var maleIndex = 0
        var used = Set<String>()
        return selected.enumerated().map { index, candidate in
            let looksFemale = candidate.0.contains { femaleHints.contains($0) }
            let preferredPool = looksFemale ? femaleNames : maleNames
            let preferredIndex = looksFemale ? femaleIndex : maleIndex
            if looksFemale { femaleIndex += 1 } else { maleIndex += 1 }
            let preferred = preferredIndex < preferredPool.count ? preferredPool[preferredIndex] : ""
            let target = usableFallback(
                preferred: preferred,
                sourceName: candidate.0,
                used: used,
                fallbackOffset: index
            )
            used.insert(target)
            return CharacterProfile(
                id: "character-\(index + 1)",
                sourceName: candidate.0,
                targetName: target,
                role: index == 0 ? "核心主角" : index < 3 ? "主要角色" : "关键配角",
                traits: index == 0 ? ["韧性", "机敏", "成长型"] : ["强动机", "关系驱动"],
                occurrences: candidate.1,
                locked: false,
                nameSource: .local
            )
        }
    }

    static func resolveModelNames(
        characters: [CharacterProfile],
        proposals: [RenameProposal]
    ) -> [CharacterProfile] {
        let proposed = Dictionary(
            proposals.map { ($0.sourceName.trimmingCharacters(in: .whitespaces), $0.targetName) },
            uniquingKeysWith: { first, _ in first }
        )
        var used = Set<String>()
        return characters.enumerated().map { index, original in
            var character = original
            let candidate = proposed[original.sourceName]?
                .replacingOccurrences(of: " ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let target = isUsable(candidate, sourceName: original.sourceName, used: used)
                ? candidate
                : usableFallback(
                    preferred: original.targetName,
                    sourceName: original.sourceName,
                    used: used,
                    fallbackOffset: index
                )
            used.insert(target)
            character.targetName = target
            character.locked = true
            character.nameSource = candidate == target ? .model : .local
            return character
        }
    }

    static func applyRenames(_ text: String, characters: [CharacterProfile]) -> String {
        characters
            .filter { !$0.sourceName.isEmpty && !$0.targetName.isEmpty }
            .sorted { $0.sourceName.count > $1.sourceName.count }
            .reduce(text) { output, character in
                output.replacingOccurrences(of: character.sourceName, with: character.targetName)
            }
    }

    static func validate(_ characters: [CharacterProfile]) -> Bool {
        let targets = characters.map { $0.targetName.trimmingCharacters(in: .whitespaces) }
        return !targets.contains(where: \.isEmpty)
            && Set(targets).count == targets.count
            && !characters.contains(where: { $0.sourceName == $0.targetName })
            && !targets.contains(where: isGenericName)
    }

    static func isGenericName(_ value: String) -> Bool {
        value.range(of: genericNamePattern, options: .regularExpression) != nil
    }

    private static func usableFallback(
        preferred: String,
        sourceName: String,
        used: Set<String>,
        fallbackOffset: Int
    ) -> String {
        if isUsable(preferred, sourceName: sourceName, used: used) { return preferred }
        let rotated = Array(fallbackNames.dropFirst(fallbackOffset % fallbackNames.count))
            + Array(fallbackNames.prefix(fallbackOffset % fallbackNames.count))
        return rotated.first { isUsable($0, sourceName: sourceName, used: used) } ?? "顾新言"
    }

    private static func isUsable(_ value: String, sourceName: String, used: Set<String>) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (2...4).contains(trimmed.count)
            && trimmed.allSatisfy { $0.unicodeScalars.allSatisfy { scalar in
                (0x4E00...0x9FFF).contains(Int(scalar.value))
            } }
            && !isGenericName(trimmed)
            && trimmed != sourceName
            && !used.contains(trimmed)
    }

    private static func plausible(_ name: String) -> Bool {
        guard (2...3).contains(name.count), !invalid.contains(name) else { return false }
        guard let last = name.last, !invalidEndings.contains(last) else { return false }
        return true
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        var count = 0
        var range = text.startIndex..<text.endIndex
        while let found = text.range(of: needle, range: range) {
            count += 1
            range = found.upperBound..<text.endIndex
        }
        return count
    }

    private static func contextualBoost(name: String, in text: String) -> Int {
        let verbs = ["说", "道", "问", "答", "笑", "怒", "喊", "看", "望", "皱眉", "转身"]
        return verbs.reduce(0) { score, verb in
            score + occurrences(of: name + verb, in: text) * 3
        }
    }
}
