import type { CharacterProfile, NovelDocument } from "../domain";

const SURNAMES =
  "赵钱孙李周吴郑王冯陈褚卫蒋沈韩杨朱秦尤许何吕施张孔曹严华金魏陶姜戚谢邹喻柏水窦章云苏潘葛奚范彭郎鲁韦昌马苗凤花方俞任袁柳鲍史唐费廉岑薛雷贺倪汤滕殷罗毕郝邬安常乐于时傅皮卞齐康伍余元卜顾孟平黄和穆萧尹姚邵湛汪祁毛禹狄米贝明臧计伏成戴谈宋茅庞熊纪舒屈项祝董梁杜阮蓝闵季麻强贾路娄危江童颜郭梅盛林刁钟徐邱骆高夏蔡田樊胡凌霍虞万支柯管卢莫经房裘缪干解应宗丁宣邓郁单杭洪包诸左石崔吉龚程邢裴陆荣翁荀羊甄曲封芮储靳汲邴糜松井段富巫乌焦巴弓牧隗山谷车侯宓蓬全郗班仰秋仲伊宫宁仇栾暴甘厉戎祖武符刘景詹束龙叶幸司韶黎乔苍双闻莘党翟谭贡劳姬申扶堵冉宰郦雍璩桑桂濮牛寿通边扈燕冀浦尚农温庄晏柴瞿阎充慕连茹习宦艾鱼容向古易慎戈廖庾终暨居衡步都耿满弘匡国文寇广禄阙东欧殳沃利蔚越夔隆师巩厍聂晁勾敖融冷辛阚那简饶空曾毋沙乜养鞠须丰巢关蒯相查后荆红游竺权逯盖益桓公";

const INVALID_EXACT = new Set([
  "王八蛋",
  "小姐",
  "小姐姐",
  "先生",
  "老板",
  "同学",
  "老师",
  "师父",
  "师傅",
  "师兄",
  "师弟",
  "师姐",
  "师妹",
  "师叔",
  "师伯",
  "师祖",
  "师尊",
  "掌门",
  "宗主",
  "长老",
  "医生",
  "护士",
  "系统",
  "主角",
  "对手",
  "作者",
  "华夏",
  "江城",
  "小爷",
  "老子",
  "人家",
  "大力",
  "林中",
  "马上",
  "方才",
  "何况",
  "只是",
  "于是",
  "如果",
  "虽然",
  "当然",
  "终于",
  "已经",
  "颜色",
  "农夫",
  "农夫三",
  "时候",
  "红砖",
  "酒瓶",
  "空间系",
  "力量系",
]);
const INVALID_ENDINGS = new Set(
  "的了着过是在有和与及也都不没很更最这那哪你我他她它们啊吗呢吧呀哟哦哈城国省市县区镇村家中上下来回去后前系级者人天年日时分秒个种样般处所事物话声眼手脚头脸心边面里外间校院店路门口队方次点".split(
    "",
  ),
);
const FEMALE_HINTS = "雪瑶妍嫣琳玲萱薇倩婷晴月婉柔静茜颖蕾菲兰言溪晚";
const FEMALE_NAMES = [
  "沈知夏",
  "林妍",
  "苏清禾",
  "许昭月",
  "叶晚晴",
  "温以宁",
  "乔知意",
  "姜予安",
  "宋微澜",
  "顾南枝",
];
const MALE_NAMES = [
  "程野",
  "周骁",
  "顾川",
  "陆沉舟",
  "贺砚",
  "秦越",
  "裴峥",
  "江屿",
  "沈砚",
  "谢临",
  "傅言川",
  "陈既明",
];
const FALLBACK_NAMES = [
  "程野",
  "沈知夏",
  "顾川",
  "苏清禾",
  "陆沉舟",
  "许昭月",
  "贺砚",
  "叶晚晴",
  "秦越",
  "温以宁",
  "裴峥",
  "乔知意",
  "江屿",
  "姜予安",
  "沈砚",
  "宋微澜",
  "谢临",
  "顾南枝",
  "傅言川",
  "陈既明",
];
const GENERIC_CHARACTER_NAME =
  /^(?:角色|人物|主角|配角|男主|女主|男配|女配|路人|甲|乙|丙|丁)\s*\d*$/u;

export interface ModelCharacterRename {
  sourceName: string;
  targetName: string;
}

function occurrences(text: string, needle: string) {
  let count = 0;
  let offset = 0;
  while ((offset = text.indexOf(needle, offset)) >= 0) {
    count += 1;
    offset += needle.length;
  }
  return count;
}

function contextualBoost(text: string, name: string) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const expression = new RegExp(
    `${escaped}(?:说|道|问|答|笑|怒|喊|看|望|皱|愣|点头|摇头|起身|转身)|(?:看向|望向|拉住|拦住|叫住|找到)${escaped}`,
    "g",
  );
  return (text.match(expression) || []).length * 3;
}

function isPlausibleName(value: string) {
  if (INVALID_EXACT.has(value)) return false;
  if (value.length < 2 || value.length > 3) return false;
  if (INVALID_ENDINGS.has(value.at(-1) || "")) return false;
  if (/^(这个|那个|什么|怎么|为何|因为|所以|但是|不过|没有|还有)/.test(value)) return false;
  return true;
}

export function isPlausibleSourceCharacterName(value: string) {
  return isPlausibleName(value.trim());
}

export function extractCharacters(
  document: NovelDocument,
  limit = 8,
): CharacterProfile[] {
  const text = document.chapters.map((chapter) => chapter.content).join("\n");
  const seeds = new Set<string>();
  for (let index = 0; index < text.length - 1; index += 1) {
    if (!SURNAMES.includes(text[index])) continue;
    seeds.add(text.slice(index, index + 2));
    if (index + 2 < text.length) seeds.add(text.slice(index, index + 3));
  }

  const ranked = [...seeds]
    .filter(isPlausibleName)
    .map((name) => {
      const count = occurrences(text, name);
      return { name, count, score: count + contextualBoost(text, name) };
    })
    .filter((candidate) => candidate.count >= 2)
    .sort((a, b) => b.score - a.score || b.count - a.count || b.name.length - a.name.length);

  const selected: typeof ranked = [];
  for (const candidate of ranked) {
    if (
      selected.some(
        (existing) =>
          existing.name.includes(candidate.name) ||
          candidate.name.includes(existing.name),
      )
    ) {
      continue;
    }
    selected.push(candidate);
    if (selected.length >= limit) break;
  }

  let femaleIndex = 0;
  let maleIndex = 0;
  const usedTargets = new Set<string>();
  return selected.map((candidate, index) => {
    const looksFemale = [...candidate.name].some((char) => FEMALE_HINTS.includes(char));
    const pool = looksFemale ? FEMALE_NAMES : MALE_NAMES;
    let targetName = pool[looksFemale ? femaleIndex++ : maleIndex++];
    if (!targetName || usedTargets.has(targetName)) {
      targetName =
        FALLBACK_NAMES.find(
          (name) => !usedTargets.has(name) && name !== candidate.name,
        ) || `新名${index + 1}`;
    }
    usedTargets.add(targetName);
    return {
      id: `character-${index + 1}`,
      sourceName: candidate.name,
      targetName,
      role: index === 0 ? "核心主角" : index < 3 ? "主要角色" : "关键配角",
      traits: index === 0 ? ["韧性", "机敏", "成长型"] : ["强动机", "关系驱动"],
      occurrences: candidate.count,
      locked: false,
      nameSource: "local",
    };
  });
}

export function isGenericCharacterName(value: string) {
  return GENERIC_CHARACTER_NAME.test(value.trim());
}

function isUsableModelName(
  value: string,
  sourceName: string,
  usedNames: Set<string>,
) {
  const name = value.trim().replace(/\s/g, "");
  return (
    /^[\p{Script=Han}]{2,4}$/u.test(name) &&
    !isGenericCharacterName(name) &&
    name !== sourceName &&
    !usedNames.has(name)
  );
}

/**
 * Applies one compact model naming response and guarantees that malformed model
 * names can never leak placeholders such as “角色8” into the script.
 */
export function resolveModelCharacterNames(
  characters: CharacterProfile[],
  renames: ModelCharacterRename[],
  reservedNames: string[] = [],
): CharacterProfile[] {
  const bySourceName = new Map(
    renames.map((item) => [
      item.sourceName.trim(),
      item.targetName.trim().replace(/\s/g, ""),
    ]),
  );
  const usedNames = new Set(
    reservedNames.map((name) => name.trim()).filter(Boolean),
  );
  return characters.map((character, index) => {
    const proposed = bySourceName.get(character.sourceName.trim()) || "";
    let targetName = proposed;
    if (!isUsableModelName(targetName, character.sourceName, usedNames)) {
      targetName =
        FALLBACK_NAMES.find(
          (name) =>
            isUsableModelName(name, character.sourceName, usedNames),
        ) || `顾新言`;
    }
    if (usedNames.has(targetName)) {
      targetName = `${FALLBACK_NAMES[index % FALLBACK_NAMES.length]}新`;
    }
    usedNames.add(targetName);
    return {
      ...character,
      targetName,
      locked: true,
      nameSource: "model",
    };
  });
}

export function applyRenames(text: string, characters: CharacterProfile[]) {
  return [...characters]
    .filter((character) => character.sourceName && character.targetName)
    .sort((a, b) => b.sourceName.length - a.sourceName.length)
    .reduce(
      (content, character) =>
        content.split(character.sourceName).join(character.targetName),
      text,
    );
}

export function assertValidRenameMap(characters: CharacterProfile[]) {
  const targets = characters.map((character) => character.targetName.trim());
  if (targets.some((name) => !name)) throw new Error("人物新名字不能为空");
  if (targets.some(isGenericCharacterName)) {
    throw new Error("人物新名字不能使用“角色8”一类占位名");
  }
  if (new Set(targets).size !== targets.length) throw new Error("人物新名字不能重复");
  if (
    characters.some(
      (character) => character.sourceName.trim() === character.targetName.trim(),
    )
  ) {
    throw new Error("主要人物必须完成改名后才能生成");
  }
}
