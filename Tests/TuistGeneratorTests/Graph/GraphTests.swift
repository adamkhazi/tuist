import Basic
import Foundation
import TuistCore
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator

final class GraphErrorTests: XCTestCase {
    func test_description_when_unsupportedFileExtension() {
        let error = GraphError.unsupportedFileExtension("type")
        let description = "Could't obtain product file extension for product type: type"
        XCTAssertEqual(error.description, description)
    }

    func test_type_when_unsupportedFileExtension() {
        let error = GraphError.unsupportedFileExtension("type")
        XCTAssertEqual(error.type, .bug)
    }
}

final class GraphTests: XCTestCase {
    var system: MockSystem!

    override func setUp() {
        super.setUp()
        system = MockSystem()
    }

    func test_frameworks() throws {
        let framework = FrameworkNode(path: AbsolutePath("/path/to/framework.framework"))
        let cache = GraphLoaderCache()
        cache.add(precompiledNode: framework)
        let graph = Graph.test(cache: cache)
        XCTAssertTrue(graph.frameworks.contains(framework))
    }

    func test_targetDependencies() throws {
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "Dependency", product: .staticLibrary)
        let project = Project.test(targets: [target, dependency])
        let dependencyNode = TargetNode(project: project,
                                        target: dependency,
                                        dependencies: [])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [dependencyNode])
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)
        let dependencies = graph.targetDependencies(path: project.path,
                                                    name: target.name)
        XCTAssertEqual(dependencies.first?.target.name, "Dependency")
    }

    func test_linkableDependencies_whenPrecompiled() throws {
        let target = Target.test(name: "Main")
        let precompiledNode = FrameworkNode(path: AbsolutePath("/test/test.framework"))
        let project = Project.test(targets: [target])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [precompiledNode])
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)

        system.succeedCommand("/usr/bin/lipo", "-info", "/test/test.framework/test",
                              output: "Architectures in the fat file: Alamofire are: x86_64 arm64")

        let got = try graph.linkableDependencies(path: project.path,
                                                 name: target.name,
                                                 system: system)
        XCTAssertEqual(got.first, .absolute(precompiledNode.path))
    }

    func test_linkableDependencies_whenALibraryTarget() throws {
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "Dependency", product: .staticLibrary)
        let project = Project.test(targets: [target])
        let dependencyNode = TargetNode(project: project,
                                        target: dependency,
                                        dependencies: [])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [dependencyNode])
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)
        let got = try graph.linkableDependencies(path: project.path,
                                                 name: target.name,
                                                 system: system)
        XCTAssertEqual(got.first, .product(target: "Dependency"))
    }

    func test_linkableDependencies_whenAFrameworkTarget() throws {
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "Dependency", product: .framework)
        let staticDependency = Target.test(name: "StaticDependency", product: .staticLibrary)
        let project = Project.test(targets: [target])

        let staticDependencyNode = TargetNode(project: project,
                                              target: staticDependency,
                                              dependencies: [])
        let dependencyNode = TargetNode(project: project,
                                        target: dependency,
                                        dependencies: [staticDependencyNode])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [dependencyNode])

        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        cache.add(targetNode: dependencyNode)
        cache.add(targetNode: staticDependencyNode)

        let graph = Graph.test(cache: cache)
        let got = try graph.linkableDependencies(path: project.path,
                                                 name: target.name,
                                                 system: system)
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got.first, .product(target: "Dependency"))

        let frameworkGot = try graph.linkableDependencies(path: project.path,
                                                          name: dependency.name,
                                                          system: system)

        XCTAssertEqual(frameworkGot.count, 1)
        XCTAssertTrue(frameworkGot.contains(.product(target: "StaticDependency")))
    }

    func test_librariesPublicHeaders() throws {
        let target = Target.test(name: "Main")
        let publicHeadersPath = AbsolutePath("/test/public/")
        let precompiledNode = LibraryNode(path: AbsolutePath("/test/test.a"),
                                          publicHeaders: publicHeadersPath)
        let project = Project.test(targets: [target])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [precompiledNode])
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)
        let got = graph.librariesPublicHeadersFolders(path: project.path,
                                                      name: target.name)
        XCTAssertEqual(got.first, publicHeadersPath)
    }

    func test_embeddableFrameworks_when_targetIsNotApp() throws {
        let target = Target.test(name: "Main", product: .framework)
        let dependency = Target.test(name: "Dependency", product: .framework)
        let project = Project.test(targets: [target])
        let dependencyNode = TargetNode(project: project,
                                        target: dependency,
                                        dependencies: [])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [dependencyNode])
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)
        system.succeedCommand([], output: "dynamically linked")

        let got = try graph.embeddableFrameworks(path: project.path,
                                                 name: target.name,
                                                 system: system)

        XCTAssertNil(got.first)
    }

    func test_embeddableFrameworks_when_dependencyIsATarget() throws {
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "Dependency", product: .framework)
        let project = Project.test(targets: [target])
        let dependencyNode = TargetNode(project: project,
                                        target: dependency,
                                        dependencies: [])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [dependencyNode])
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)

        system.succeedCommand([], output: "dynamically linked")
        let got = try graph.embeddableFrameworks(path: project.path,
                                                 name: target.name,
                                                 system: system)
        XCTAssertEqual(got.first, DependencyReference.product(target: "Dependency"))
    }

    func test_embeddableFrameworks_when_dependencyIsAFramework() throws {
        let frameworkPath = AbsolutePath("/test/test.framework")
        let target = Target.test(name: "Main", platform: .iOS)
        let frameworkNode = FrameworkNode(path: frameworkPath)
        let project = Project.test(targets: [target])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [frameworkNode])
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)

        system.succeedCommand("/usr/bin/file", "/test/test.framework/test",
                              output: "dynamically linked")

        let got = try graph.embeddableFrameworks(path: project.path,
                                                 name: target.name,
                                                 system: system)

        XCTAssertEqual(got.first, DependencyReference.absolute(frameworkPath))
    }

    func test_embeddableFrameworks_when_dependencyIsATransitiveFramework() throws {
        let target = Target.test(name: "Main")
        let dependency = Target.test(name: "Dependency", product: .framework)
        let project = Project.test(targets: [target])

        let frameworkPath = AbsolutePath("/test/test.framework")
        let frameworkNode = FrameworkNode(path: frameworkPath)

        let dependencyNode = TargetNode(
            project: project,
            target: dependency,
            dependencies: [frameworkNode]
        )
        let targetNode = TargetNode(
            project: project,
            target: target,
            dependencies: [dependencyNode]
        )
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)

        system.succeedCommand("/usr/bin/file", "/test/test.framework/test",
                              output: "dynamically linked")

        let got = try graph.embeddableFrameworks(
            path: project.path,
            name: target.name,
            system: system
        )

        XCTAssertEqual(got, [
            DependencyReference.product(target: "Dependency"),
            DependencyReference.absolute(frameworkPath),
        ])
    }

    func test_embeddableFrameworks_ordered() throws {
        // Given
        let dependencyNames = (0 ..< 10).shuffled().map { "Dependency\($0)" }
        let target = Target.test(name: "Main", product: .app)
        let project = Project.test(targets: [target])
        let dependencyNodes = dependencyNames.map {
            TargetNode(project: project,
                       target: Target.test(name: $0, product: .framework),
                       dependencies: [])
        }
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: dependencyNodes)
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)

        // When
        let got = try graph.embeddableFrameworks(path: project.path,
                                                 name: target.name,
                                                 system: system)

        // Then
        let expected = dependencyNames.sorted().map { DependencyReference.product(target: $0) }
        XCTAssertEqual(got, expected)
    }

    func test_librariesSearchPaths() throws {
        // Given
        let target = Target.test(name: "Main")
        let precompiledNode = LibraryNode(path: AbsolutePath("/test/test.a"),
                                          publicHeaders: AbsolutePath("/test/public/"))
        let project = Project.test(targets: [target])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [precompiledNode])
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)

        // When
        let got = graph.librariesSearchPaths(path: project.path,
                                             name: target.name)

        // Then
        XCTAssertEqual(got, [AbsolutePath("/test")])
    }

    func test_librariesSwiftIncludePaths() throws {
        // Given
        let target = Target.test(name: "Main")
        let precompiledNodeA = LibraryNode(path: AbsolutePath("/test/test.a"),
                                           publicHeaders: AbsolutePath("/test/public/"),
                                           swiftModuleMap: AbsolutePath("/test/modules/test.swiftmodulemap"))
        let precompiledNodeB = LibraryNode(path: AbsolutePath("/test/another.a"),
                                           publicHeaders: AbsolutePath("/test/public/"),
                                           swiftModuleMap: nil)
        let project = Project.test(targets: [target])
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [precompiledNodeA, precompiledNodeB])
        let cache = GraphLoaderCache()
        cache.add(targetNode: targetNode)
        let graph = Graph.test(cache: cache)

        // When
        let got = graph.librariesSwiftIncludePaths(path: project.path,
                                                   name: target.name)

        // Then
        XCTAssertEqual(got, [AbsolutePath("/test/modules")])
    }

    func test_resourceBundleDependencies_fromTargetDependency() {
        // Given
        let bundle = Target.test(name: "Bundle1", product: .bundle)
        let app = Target.test(name: "App", product: .bundle)
        let projectA = Project.test(path: "/path/a")

        let graph = Graph.create(project: projectA,
                                 dependencies: [
                                     (target: bundle, dependencies: []),
                                     (target: app, dependencies: [bundle]),
                                 ])

        // When
        let result = graph.resourceBundleDependencies(path: projectA.path, name: app.name)

        // Then
        XCTAssertEqual(result.map(\.target.name), [
            "Bundle1",
        ])
    }

    func test_resourceBundleDependencies_fromProjectDependency() {
        // Given
        let bundle = Target.test(name: "Bundle1", product: .bundle)
        let projectA = Project.test(path: "/path/a")

        let app = Target.test(name: "App", product: .app)
        let projectB = Project.test(path: "/path/b")

        let graph = Graph.create(projects: [projectA, projectB],
                                 dependencies: [
                                     (project: projectA, target: bundle, dependencies: []),
                                     (project: projectB, target: app, dependencies: [bundle]),
                                 ])

        // When
        let result = graph.resourceBundleDependencies(path: projectB.path, name: app.name)

        // Then
        XCTAssertEqual(result.map(\.target.name), [
            "Bundle1",
        ])
    }

    func test_encode() {
        // Given
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)
        let framework = FrameworkNode(path: fixturePath(path: RelativePath("xpm.framework")))
        let library = LibraryNode(path: fixturePath(path: RelativePath("libStaticLibrary.a")),
                                  publicHeaders: fixturePath(path: RelativePath("")))
        let target = TargetNode.test(dependencies: [framework, library])
        cache.add(targetNode: target)
        cache.add(precompiledNode: framework)
        cache.add(precompiledNode: library)

        let expected = """
        [
            {
              "path" : "\(library.path)",
              "architectures" : [
                "x86_64"
              ],
              "product" : "static_library",
              "name" : "\(library.name)",
              "type" : "precompiled"
            },
            {
              "path" : "\(framework.path)",
              "architectures" : [
                "x86_64",
                "arm64"
              ],
              "product" : "framework",
              "name" : "\(framework.name)",
              "type" : "precompiled"
            },
            {
              "product" : "\(target.target.product.rawValue)",
              "bundle_id" : "\(target.target.bundleId)",
              "platform" : "\(target.target.platform.rawValue)",
              "path" : "\(target.path)",
              "dependencies" : [
                "xpm",
                "libStaticLibrary"
              ],
              "name" : "Target",
              "type" : "source"
            }
        ]
        """

        // Then
        XCTAssertEncodableEqualToJson(graph, expected)
    }
}

final class DependencyReferenceTests: XCTestCase {
    func test_equal() {
        let subjects: [(DependencyReference, DependencyReference, Bool)] = [
            // Absolute
            (.absolute(.init("/a.framework")), .absolute(.init("/a.framework")), true),
            (.absolute(.init("/a.framework")), .product(target: "Main"), false),
            (.absolute(.init("/a.framework")), .sdk(.init("/CoreData.framework"), .required), false),

            // Product
            (.product(target: "Main"), .product(target: "Main"), true),
            (.product(target: "Main"), .absolute(.init("/a.framework")), false),
            (.product(target: "Main"), .sdk(.init("/CoreData.framework"), .required), false),
            (.product(target: "Main-iOS"), .product(target: "Main-macOS"), false),

            // SDK
            (.sdk(.init("/CoreData.framework"), .required), .sdk(.init("/CoreData.framework"), .required), true),
            (.sdk(.init("/CoreData.framework"), .required), .product(target: "Main"), false),
            (.sdk(.init("/CoreData.framework"), .required), .absolute(.init("/a.framework")), false),
        ]

        XCTAssertEqualPairs(subjects)
    }

    func test_compare() {
        XCTAssertFalse(DependencyReference.absolute("/A") < .absolute("/A"))
        XCTAssertTrue(DependencyReference.absolute("/A") < .absolute("/B"))
        XCTAssertFalse(DependencyReference.absolute("/B") < .absolute("/A"))

        XCTAssertFalse(DependencyReference.product(target: "A") < .product(target: "A"))
        XCTAssertTrue(DependencyReference.product(target: "A") < .product(target: "B"))
        XCTAssertFalse(DependencyReference.product(target: "B") < .product(target: "A"))

        XCTAssertTrue(DependencyReference.product(target: "/A") < .absolute("/A"))
        XCTAssertTrue(DependencyReference.product(target: "/A") < .absolute("/B"))
        XCTAssertTrue(DependencyReference.product(target: "/B") < .absolute("/A"))

        XCTAssertFalse(DependencyReference.absolute("/A") < .product(target: "/A"))
        XCTAssertFalse(DependencyReference.absolute("/A") < .product(target: "/B"))
        XCTAssertFalse(DependencyReference.absolute("/B") < .product(target: "/A"))
    }
}
