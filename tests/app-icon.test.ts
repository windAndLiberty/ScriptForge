import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

interface PackageManifest {
  scripts: Record<string, string>;
  build: {
    files: string[];
    win: { icon: string };
  };
}

function pngDimensions(filePath: string) {
  const value = fs.readFileSync(filePath);
  expect(value.subarray(1, 4).toString("ascii")).toBe("PNG");
  return {
    width: value.readUInt32BE(16),
    height: value.readUInt32BE(20),
  };
}

function sha256(filePath: string) {
  return crypto
    .createHash("sha256")
    .update(fs.readFileSync(filePath))
    .digest("hex");
}

describe("cross-platform application icon", () => {
  it("packages the same Aura artwork used by the macOS app", () => {
    const root = process.cwd();
    const windowsIcon = path.join(root, "build", "icon-aura.png");
    const macOSIcon = path.join(
      root,
      "macos",
      "Sources",
      "ScriptForgeMac",
      "Resources",
      "ScriptForgeAura.png",
    );
    const manifest = JSON.parse(
      fs.readFileSync(path.join(root, "package.json"), "utf8"),
    ) as PackageManifest;
    const electronMain = fs.readFileSync(
      path.join(root, "electron", "main.cjs"),
      "utf8",
    );

    expect(sha256(windowsIcon)).toBe(sha256(macOSIcon));
    expect(manifest.build.win.icon).toBe("build/icon-aura.png");
    expect(manifest.build.files).toContain("build/icon-aura.png");
    expect(electronMain).toContain('../build/icon-aura.png');
    expect(manifest.scripts["dist:windows:store"]).toContain(
      "npm run assets:windows:store",
    );
    expect(
      pngDimensions(path.join(root, "build", "appx", "StoreLogo.png")),
    ).toEqual({ width: 50, height: 50 });
    expect(
      pngDimensions(
        path.join(root, "build", "appx", "Square44x44Logo.png"),
      ),
    ).toEqual({ width: 44, height: 44 });
    expect(
      pngDimensions(
        path.join(root, "build", "appx", "Square150x150Logo.png"),
      ),
    ).toEqual({ width: 150, height: 150 });
    expect(
      pngDimensions(
        path.join(root, "build", "appx", "Wide310x150Logo.png"),
      ),
    ).toEqual({ width: 310, height: 150 });
  });
});
