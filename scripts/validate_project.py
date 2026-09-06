#!/usr/bin/env python3
import json
import pathlib
import plistlib
import subprocess
import xml.etree.ElementTree as ET

root = pathlib.Path(__file__).resolve().parents[1]
project = root / "Sufler.xcodeproj/project.pbxproj"
payload = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(project)]))
objects = payload["objects"]
for value in objects.values():
    if value["isa"] == "PBXFileReference" and value.get("sourceTree") == "SOURCE_ROOT":
        assert (root / value["path"]).exists(), value["path"]
    if value["isa"] == "PBXBuildFile":
        assert value["fileRef"] in objects
    if value["isa"] == "PBXNativeTarget":
        assert value["buildConfigurationList"] in objects
        for phase in value["buildPhases"]:
            assert phase in objects

referenced = {v.get("path") for v in objects.values() if v["isa"] == "PBXFileReference"}
for folder in ["Sufler", "Tests"]:
    for source in (root / folder).rglob("*.swift"):
        assert str(source.relative_to(root)) in referenced, source

info = plistlib.loads((root / "Sufler/Resources/Info.plist").read_bytes())
assert info["UISupportedInterfaceOrientations"] == ["UIInterfaceOrientationPortrait"]
for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSPhotoLibraryAddUsageDescription"]:
    assert info[key]
privacy = plistlib.loads((root / "Sufler/Resources/PrivacyInfo.xcprivacy").read_bytes())
assert not privacy["NSPrivacyTracking"]
assert not privacy["NSPrivacyCollectedDataTypes"]
ET.parse(root / "Sufler.xcodeproj/xcshareddata/xcschemes/Sufler.xcscheme")
for file in (root / "Sufler/Resources/Assets.xcassets").rglob("Contents.json"):
    json.loads(file.read_text())
sources = sorted((root / "Sufler").rglob("*.swift"))
subprocess.run(["swiftc", "-frontend", "-parse", *map(str, sources)], check=True)
print(f"PASS: project references, scheme XML, privacy/permissions, assets, Swift syntax ({len(sources)} app files)")

