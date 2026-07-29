import Foundation

enum CharacterExtractor {
    private static let surnames = Set(
        "赵钱孙李周吴郑王冯陈褚卫蒋沈韩杨朱秦许何吕施张孔曹严华金魏陶姜谢邹苏潘葛范彭鲁韦昌马苗方任袁柳史唐费廉岑薛雷贺倪汤滕殷罗毕郝安常乐于时傅齐康伍余顾孟平黄穆萧尹姚邵汪毛米贝明成戴宋熊纪舒项祝董梁杜蓝季贾路江童颜郭梅盛林钟徐邱骆高夏蔡田樊胡凌霍虞万卢莫房左石崔吉龚程邢裴陆荣翁段富焦巴牧谷车侯全班秋仲宫宁甘厉祖武刘景龙叶黎乔闻党谭申艾向古易慎廖冷辛曾沙关红游权"
    )
    private static let invalid: Set<String> = [
        "王八蛋", "小姐", "小姐姐", "先生", "老板", "同学", "老师", "医生",
        "护士", "系统", "主角", "对手", "作者", "华夏", "江城", "小爷",
        "老子", "人家", "大力", "颜色", "农夫", "农夫三", "时候", "红砖",
        "酒瓶", "空间系", "力量系", "马上", "于是", "如果", "虽然", "已经",
    ]
    private static let invalidEndings = Set(
        "的了着过是在有和与及也都不没这那你我他她它们啊吗呢吧城国省市县区镇村家中上下后前系级者人天年日时分秒个种样处所事物话声眼手脚头脸心边面里外间校院店路门口队方次点"
    )
    private static let femaleHints = Set("雪瑶妍嫣琳玲萱薇倩婷晴月婉柔静茜颖蕾菲兰言溪晚")
    private static let femaleNames = ["沈知夏", "林妍", "苏清禾", "许昭月", "叶晚晴"]
    private static let maleNames = ["程野", "周骁", "顾川", "陆沉舟", "贺砚", "秦越", "裴峥"]

    static func extract(from document: NovelDocument, limit: Int = 8) -> [CharacterProfile] {
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

        let ranked = seeds.compactMap { name -> (String, Int)? in
            guard plausible(name) else { return nil }
            let count = occurrences(of: name, in: text)
            guard count >= 2 else { return nil }
            return (name, count)
        }.sorted {
            if $0.1 == $1.1 { return $0.0.count > $1.0.count }
            return $0.1 > $1.1
        }

        var selected: [(String, Int)] = []
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
            let pool = looksFemale ? femaleNames : maleNames
            let poolIndex = looksFemale ? femaleIndex : maleIndex
            var target = poolIndex < pool.count ? pool[poolIndex] : "角色\(index + 1)"
            if looksFemale { femaleIndex += 1 } else { maleIndex += 1 }
            if used.contains(target) { target = "角色\(index + 1)" }
            used.insert(target)
            return CharacterProfile(
                id: "character-\(index + 1)",
                sourceName: candidate.0,
                targetName: target,
                role: index == 0 ? "核心主角" : index < 3 ? "主要角色" : "关键配角",
                traits: index == 0 ? ["韧性", "机敏", "成长型"] : ["强动机", "关系驱动"],
                occurrences: candidate.1,
                locked: true
            )
        }
    }

    static func applyRenames(_ text: String, characters: [CharacterProfile]) -> String {
        characters
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
}
