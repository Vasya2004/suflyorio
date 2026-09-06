#!/usr/bin/env python3
"""Run the shared pure-Swift tests even when only Command Line Tools are installed.

No app types or SDKs are mocked. Swift Testing's assertion/test annotations are
translated to a small throwing assertion harness; test bodies stay identical.
SwiftData and camera tests still require full Xcode.
"""
import pathlib
import re
import subprocess
import os

root = pathlib.Path(__file__).resolve().parents[1]
build = root / ".build" / "standalone-checks"
build.mkdir(parents=True, exist_ok=True)
sources = []
calls = []
for path in sorted((root / "Tests/SuflerCoreTests").glob("*.swift")):
    source = path.read_text()
    for name, asynchronous, throwing in re.findall(r"@Test func (\w+)\(\)( async)?( throws)?", source):
        calls.append(("try " if throwing else "") + ("await " if asynchronous else "") + name + "()")
    source = re.sub(r"#if SWIFT_PACKAGE\n@testable import SuflerCore\n#else\n@testable import Sufler\n#endif\n", "", source)
    source = re.sub(r"^import Testing\n", "", source, flags=re.M)
    source = source.replace("@Test ", "").replace("#expect(", "check(")
    sources.append(source)
harness = '''
import Foundation
func check(_ expression: @autoclosure () throws -> Bool, file: StaticString = #file, line: UInt = #line) {
    do { if try !expression() { fatalError("Check failed", file: file, line: line) } }
    catch { fatalError("Unexpected error: \\(error)", file: file, line: line) }
}
'''
harness += "\n".join(sources)
harness += "\n@main enum CoreChecks { static func main() async throws {\n"
for call in calls:
    harness += "    " + call + "\n"
harness += f'    print("PASS: {len(calls)} core tests (shared test bodies)")\n' + "} }\n"
generated = build / "CoreChecks.swift"
generated.write_text(harness)
executable = build / "core-checks"
subprocess.run(["swiftc", "-parse-as-library", "-D", "STANDALONE_CHECKS", *map(str, sorted((root / "Sufler/Core").glob("*.swift"))), str(generated), "-o", str(executable)], check=True)
subprocess.run([str(executable)], check=True, env={**os.environ, "SUFLER_FIXTURES": str(root / "Tests/SuflerCoreTests/Fixtures")})
