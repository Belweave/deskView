#!/usr/bin/env python3
"""Generate the small, reviewable Xcode app project using only Python's stdlib."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "DeskView.xcodeproj"
objects = {}

def oid(label):
    return hashlib.sha256(label.encode()).hexdigest()[:24].upper()

def add(label, isa, **fields):
    key = oid(label)
    objects[key] = {"isa": isa, **fields}
    return key

def ref(value):
    return ("REF", value)

def encode(value, depth=0):
    if isinstance(value, tuple):
        return value[1]
    if isinstance(value, dict):
        pad = "\t" * depth
        return "{\n" + "".join(f"{pad}\t{k} = {encode(v, depth+1)};\n" for k, v in value.items()) + pad + "}"
    if isinstance(value, list):
        return "(" + ", ".join(encode(v, depth) for v in value) + ")"
    if isinstance(value, int):
        return str(value)
    return json.dumps(value)

swift_files = sorted((ROOT / "App").glob("*.swift"))
file_refs = []
build_files = []
for file in swift_files:
    f = add("file:" + file.name, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=file.name, sourceTree="<group>")
    file_refs.append(ref(f))
    build_files.append(ref(add("build:" + file.name, "PBXBuildFile", fileRef=ref(f))))
for name, kind in [("Info.plist", "text.plist.xml"), ("DeskView.entitlements", "text.plist.entitlements")]:
    file_refs.append(ref(add("file:" + name, "PBXFileReference", lastKnownFileType=kind, path=name, sourceTree="<group>")))

app_group = add("App", "PBXGroup", path="App", sourceTree="<group>", children=file_refs)
product = add("product", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0, path="deskView().app", sourceTree="BUILT_PRODUCTS_DIR")
products = add("products", "PBXGroup", name="Products", sourceTree="<group>", children=[ref(product)])
main = add("main", "PBXGroup", sourceTree="<group>", children=[ref(app_group), ref(products)])
local_package = add("localPackage", "XCLocalSwiftPackageReference", relativePath=".")
foyer_package = add("FoyerPackage", "XCRemoteSwiftPackageReference", repositoryURL="https://github.com/Belweave/FoyerKit.git", requirement={"kind": "revision", "revision": "9b4ed7e5d3fd1b208b59c1675fdbf48e66c54509"})
kit = add("kitProduct", "XCSwiftPackageProductDependency", productName="DeskViewKit")
foyer = add("foyerProduct", "XCSwiftPackageProductDependency", package=ref(foyer_package), productName="FoyerKit")
frameworks = add("frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[
    ref(add("linkKit", "PBXBuildFile", productRef=ref(kit))),
    ref(add("linkFoyer", "PBXBuildFile", productRef=ref(foyer)))
], runOnlyForDeploymentPostprocessing=0)
sources = add("sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=build_files, runOnlyForDeploymentPostprocessing=0)
resources = add("resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
for resource in sorted((ROOT / "App" / "Resources").glob("*.txt")):
    resource_ref = add("resource:" + resource.name, "PBXFileReference", lastKnownFileType="text", path="Resources/" + resource.name, sourceTree="<group>")
    objects[app_group]["children"].append(ref(resource_ref))
    objects[resources]["files"].append(ref(add("resourceBuild:" + resource.name, "PBXBuildFile", fileRef=ref(resource_ref))))
asset_path = ROOT / "App" / "Assets.xcassets"
if asset_path.exists():
    asset_ref = add("assets", "PBXFileReference", lastKnownFileType="folder.assetcatalog", path="Assets.xcassets", sourceTree="<group>")
    objects[app_group]["children"].append(ref(asset_ref))
    objects[resources]["files"].append(ref(add("assetBuild", "PBXBuildFile", fileRef=ref(asset_ref))))

project_configs = []
target_configs = []
for name in ["Debug", "Release"]:
    project_settings = {
        "ARCHS": "arm64", "SDKROOT": "macosx", "MACOSX_DEPLOYMENT_TARGET": "26.0",
        "SWIFT_VERSION": "6.0", "CLANG_ENABLE_MODULES": "YES",
        "SWIFT_STRICT_CONCURRENCY": "complete", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "DEBUG_INFORMATION_FORMAT": "dwarf" if name == "Debug" else "dwarf-with-dsym",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if name == "Debug" else "-O",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if name == "Debug" else "",
        "ENABLE_TESTABILITY": "YES" if name == "Debug" else "NO",
    }
    project_configs.append(ref(add("project" + name, "XCBuildConfiguration", name=name, buildSettings=project_settings)))
    settings = {
        "PRODUCT_NAME": "DeskView", "WRAPPER_NAME": "deskView().app",
        "PRODUCT_BUNDLE_IDENTIFIER": "org.belweave.deskView",
        "INFOPLIST_FILE": "App/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
        "MARKETING_VERSION": "0.1.0", "CURRENT_PROJECT_VERSION": "1",
        "CODE_SIGN_STYLE": "Manual", "CODE_SIGN_IDENTITY": "-",
        "CODE_SIGN_ENTITLEMENTS": "App/DeskView.entitlements",
        "ENABLE_HARDENED_RUNTIME": "YES", "ENABLE_APP_SANDBOX": "NO",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"],
        "SWIFT_EMIT_LOC_STRINGS": "YES", "COMBINE_HIDPI_IMAGES": "YES",
    }
    if asset_path.exists():
        settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
    target_configs.append(ref(add("target" + name, "XCBuildConfiguration", name=name, buildSettings=settings)))
project_config_list = add("projectConfigList", "XCConfigurationList", buildConfigurations=project_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
target_config_list = add("targetConfigList", "XCConfigurationList", buildConfigurations=target_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
target = add("target", "PBXNativeTarget", name="deskView", productName="DeskView", productReference=ref(product),
             productType="com.apple.product-type.application", buildConfigurationList=ref(target_config_list),
             buildPhases=[ref(sources), ref(frameworks), ref(resources)], buildRules=[], dependencies=[],
             packageProductDependencies=[ref(kit), ref(foyer)])
project = add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "2710"},
              buildConfigurationList=ref(project_config_list), compatibilityVersion="Xcode 16.0", developmentRegion="en",
              hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=ref(main), productRefGroup=ref(products),
              projectDirPath="", projectRoot="", packageReferences=[ref(local_package), ref(foyer_package)], targets=[ref(target)])
PROJECT.mkdir(exist_ok=True)
tree = {"archiveVersion": 1, "classes": {}, "objectVersion": 77, "objects": objects, "rootObject": ref(project)}
(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode(tree) + "\n")
scheme_dir = PROJECT / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
(scheme_dir / "deskView.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2710" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="deskView().app" BlueprintName="deskView" ReferencedContainer="container:DeskView.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug"/>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="deskView().app" BlueprintName="deskView" ReferencedContainer="container:DeskView.xcodeproj"/></BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="deskView().app" BlueprintName="deskView" ReferencedContainer="container:DeskView.xcodeproj"/></BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(f"Generated DeskView.xcodeproj ({len(swift_files)} Swift files).")
