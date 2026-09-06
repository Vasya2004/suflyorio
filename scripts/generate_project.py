#!/usr/bin/env python3
"""Generate the checked-in, dependency-free Xcode project deterministically."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
project = root / "Sufler.xcodeproj"
project.mkdir(exist_ok=True)
objects = {}

def ident(key):
    return hashlib.sha256(key.encode()).hexdigest()[:24].upper()

def add(key, **fields):
    value = ident(key)
    objects[value] = fields
    return value

def file(path, kind):
    return add("file:" + path, isa="PBXFileReference", lastKnownFileType=kind, path=path, sourceTree="SOURCE_ROOT")

def build_file(ref):
    return add("build:" + ref, isa="PBXBuildFile", fileRef=ref)

def phase(name, kind, refs):
    return add(name, isa=kind, buildActionMask=2147483647, files=[build_file(ref) for ref in refs], runOnlyForDeploymentPostprocessing=0)

sources = [file(str(p.relative_to(root)), "sourcecode.swift") for p in sorted((root / "Sufler").rglob("*.swift"))]
tests = [file(str(p.relative_to(root)), "sourcecode.swift") for p in sorted((root / "Tests").rglob("*.swift"))]
assets = file("Sufler/Resources/Assets.xcassets", "folder.assetcatalog")
privacy = file("Sufler/Resources/PrivacyInfo.xcprivacy", "text.xml")
info = file("Sufler/Resources/Info.plist", "text.plist.xml")
fixture = file("Tests/SuflerStorageTests/Fixtures/valid.mov", "video.quicktime")
silent_fixture = file("Tests/SuflerCoreTests/Fixtures/no-audio.mov", "video.quicktime")
app = add("app", isa="PBXFileReference", explicitFileType="wrapper.application", path="Sufler.app", sourceTree="BUILT_PRODUCTS_DIR")
test_product = add("testProduct", isa="PBXFileReference", explicitFileType="wrapper.cfbundle", path="SuflerTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
source_group = add("sources", isa="PBXGroup", children=sources, name="Приложение", sourceTree="<group>")
resource_group = add("resources", isa="PBXGroup", children=[assets, privacy, info], name="Ресурсы", sourceTree="<group>")
test_group = add("tests", isa="PBXGroup", children=tests + [fixture, silent_fixture], name="Тесты", sourceTree="<group>")
products = add("products", isa="PBXGroup", children=[app, test_product], name="Products", sourceTree="<group>")
main = add("main", isa="PBXGroup", children=[source_group, resource_group, test_group, products], sourceTree="<group>")

def configs(name, common):
    values = []
    for mode in ["Debug", "Release"]:
        settings = dict(common)
        settings.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O", "DEBUG_INFORMATION_FORMAT": "dwarf" if mode == "Debug" else "dwarf-with-dsym"})
        if mode == "Debug":
            settings.update({"ENABLE_TESTABILITY": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)", "ONLY_ACTIVE_ARCH": "YES"})
        values.append(add(name + mode, isa="XCBuildConfiguration", buildSettings=settings, name=mode))
    return add(name + "Configs", isa="XCConfigurationList", buildConfigurations=values, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

project_configs = configs("project", {"SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "26.0", "SWIFT_VERSION": "5.0", "SWIFT_STRICT_CONCURRENCY": "complete", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES"})
app_configs = configs("app", {"PRODUCT_BUNDLE_IDENTIFIER": "com.sufler.personal.b28c9432", "PRODUCT_NAME": "$(TARGET_NAME)", "CODE_SIGN_STYLE": "Automatic", "INFOPLIST_FILE": "Sufler/Resources/Info.plist", "TARGETED_DEVICE_FAMILY": "1", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO", "MARKETING_VERSION": "1.0.0", "CURRENT_PROJECT_VERSION": "1", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks"})
app_target = add("appTarget", isa="PBXNativeTarget", buildConfigurationList=app_configs, buildPhases=[phase("appSources", "PBXSourcesBuildPhase", sources), phase("appFrameworks", "PBXFrameworksBuildPhase", []), phase("appResources", "PBXResourcesBuildPhase", [assets, privacy])], buildRules=[], dependencies=[], name="Sufler", productName="Sufler", productReference=app, productType="com.apple.product-type.application")
proxy = add("proxy", isa="PBXContainerItemProxy", containerPortal=ident("project"), proxyType=1, remoteGlobalIDString=app_target, remoteInfo="Sufler")
dependency = add("dependency", isa="PBXTargetDependency", target=app_target, targetProxy=proxy)
test_configs = configs("test", {"PRODUCT_BUNDLE_IDENTIFIER": "com.sufler.personal.b28c9432.tests", "PRODUCT_NAME": "$(TARGET_NAME)", "GENERATE_INFOPLIST_FILE": "YES", "CODE_SIGN_STYLE": "Automatic", "TARGETED_DEVICE_FAMILY": "1", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Sufler.app/Sufler", "BUNDLE_LOADER": "$(TEST_HOST)", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks"})
test_target = add("testTarget", isa="PBXNativeTarget", buildConfigurationList=test_configs, buildPhases=[phase("testSources", "PBXSourcesBuildPhase", tests), phase("testFrameworks", "PBXFrameworksBuildPhase", []), phase("testResources", "PBXResourcesBuildPhase", [fixture, silent_fixture])], buildRules=[], dependencies=[dependency], name="SuflerTests", productName="SuflerTests", productReference=test_product, productType="com.apple.product-type.bundle.unit-test")
add("project", isa="PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "2600", "TargetAttributes": {app_target: {"CreatedOnToolsVersion": "26.0"}, test_target: {"CreatedOnToolsVersion": "26.0", "TestTargetID": app_target}}}, buildConfigurationList=project_configs, compatibilityVersion="Xcode 15.0", developmentRegion="ru", hasScannedForEncodings=0, knownRegions=["ru", "en", "Base"], mainGroup=main, productRefGroup=products, projectDirPath="", projectRoot="", targets=[app_target, test_target])

def encode(value, level=0):
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (level+1) + json.dumps(k, ensure_ascii=False) + " = " + encode(v, level+1) + ";\n" for k, v in value.items()) + "\t" * level + "}"
    if isinstance(value, list): return "(" + ", ".join(encode(v, level) for v in value) + ("," if value else "") + ")"
    if isinstance(value, int): return str(value)
    return json.dumps(value, ensure_ascii=False)

payload = {"archiveVersion": 1, "classes": {}, "objectVersion": 60, "objects": objects, "rootObject": ident("project")}
(project / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode(payload) + "\n")
scheme_dir = project / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
def ref(identifier, name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:Sufler.xcodeproj"/>'
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref(app_target, "Sufler.app")}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ref(test_target, "SuflerTests.xctest")}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app_target, "Sufler.app")}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app_target, "Sufler.app")}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
(scheme_dir / "Sufler.xcscheme").write_text(scheme)
print(f"Generated {project.name}: {len(sources)} app sources, {len(tests)} test sources")
