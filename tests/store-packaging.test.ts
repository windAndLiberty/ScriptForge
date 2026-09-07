import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

interface PackageManifest {
  version: string;
  scripts: Record<string, string>;
  build: {
    appx: {
      identityName: string;
      publisher: string;
      publisherDisplayName: string;
      displayName: string;
      languages: string[];
    };
  };
}

describe("Microsoft Store packaging", () => {
  it("uses the Partner Center identity and an explicit x64 target", () => {
    const manifest = JSON.parse(
      fs.readFileSync(path.resolve(process.cwd(), "package.json"), "utf8"),
    ) as PackageManifest;

    expect(manifest.build.appx).toMatchObject({
      identityName: "YuSeTech.ScriptForge",
      publisher: "CN=5E86A6E9-6F90-4E5A-A9DA-086C3BF2C80C",
      publisherDisplayName: "YuSeTech",
      displayName: "剧擎 ScriptForge",
      languages: ["zh-CN", "en-US"],
    });
    expect(manifest.version).toBe("1.0.1");
    expect(manifest.scripts["dist:windows:store"]).toContain(
      "electron-builder --win appx --x64 --publish never",
    );
  });
});
