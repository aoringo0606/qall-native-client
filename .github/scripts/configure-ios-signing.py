"""Configure the CI checkout for manual signing of Runner and its extension."""

import datetime
import os
from pathlib import Path
import plistlib
import re
import shutil


def main():
    temporary = Path(os.environ["RUNNER_TEMP"])
    team = os.environ["TEAM_ID"]
    app_group = os.environ["APP_GROUP_ID"]
    profiles = {}
    for target, bundle_id, filename in (
        ("Runner", os.environ["BUNDLE_ID"], "app"),
        ("BroadcastExtension", os.environ["EXTENSION_BUNDLE_ID"], "extension"),
    ):
        with (temporary / f"{filename}-profile.plist").open("rb") as source:
            profile = plistlib.load(source)
        entitlements = profile["Entitlements"]
        prefix = profile["ApplicationIdentifierPrefix"][0]
        if (
            team not in profile["TeamIdentifier"]
            or entitlements["application-identifier"] != f"{prefix}.{bundle_id}"
            or app_group not in entitlements.get("com.apple.security.application-groups", [])
            or entitlements.get("get-task-allow", False)
            or "ProvisionedDevices" in profile
            or profile.get("ProvisionsAllDevices", False)
            or profile["ExpirationDate"] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
        ):
            raise ValueError(f"{target}: expected an unexpired App Store profile for {bundle_id}, team {team}, and {app_group}")
        profiles[target] = (bundle_id, profile["UUID"])
        directory = Path.home() / "Library/MobileDevice/Provisioning Profiles"
        directory.mkdir(parents=True, exist_ok=True)
        destination = directory / f'{profile["UUID"]}.mobileprovision'
        shutil.copyfile(temporary / f"{filename}.mobileprovision", destination)
        with (temporary / "installed-profile-paths.txt").open("a") as paths:
            paths.write(f"{destination}\n")

    project = Path("ios/Runner.xcodeproj/project.pbxproj")
    counts = {target: 0 for target in profiles}

    def configure(match):
        block = match.group(0)
        for target, (bundle_id, uuid) in profiles.items():
            if f"CODE_SIGN_ENTITLEMENTS = {target}/{target}.entitlements;" not in block:
                continue
            settings = {
                "CODE_SIGN_STYLE": "Manual",
                "CODE_SIGN_IDENTITY": "Apple Distribution",
                "DEVELOPMENT_TEAM": team,
                "PROVISIONING_PROFILE_SPECIFIER": uuid,
                "PRODUCT_BUNDLE_IDENTIFIER": bundle_id,
                "APP_GROUP_IDENTIFIER": app_group,
                "BROADCAST_EXTENSION_BUNDLE_IDENTIFIER": os.environ["EXTENSION_BUNDLE_ID"],
            }
            for key, value in settings.items():
                # Quote and escape values using OpenStep string syntax.
                value = value.replace("\\", "\\\\").replace('"', '\\"')
                entry = f'{key} = "{value}";'
                pattern = rf"(?m)^\s*{key} = [^\n]+;"
                block = re.sub(pattern, lambda _: "\n\t\t\t\t" + entry, block)
                if not re.search(pattern, block):
                    block = block.replace("buildSettings = {", "buildSettings = {\n\t\t\t\t" + entry, 1)
            counts[target] += 1
        return block

    updated = re.sub(r"buildSettings = \{[^{}]*\};", configure, project.read_text())
    if any(count != 3 for count in counts.values()):
        raise ValueError(f"Expected Debug/Release/Profile settings for both targets: {counts}")
    project.write_text(updated)
    with (temporary / "ExportOptions.plist").open("wb") as output:
        plistlib.dump(
            {
                "method": "app-store-connect",
                "destination": "export",
                "signingStyle": "manual",
                "teamID": team,
                "signingCertificate": "Apple Distribution",
                "manageAppVersionAndBuildNumber": False,
                "provisioningProfiles": dict(profiles.values()),
            },
            output,
        )


if __name__ == "__main__":
    main()
