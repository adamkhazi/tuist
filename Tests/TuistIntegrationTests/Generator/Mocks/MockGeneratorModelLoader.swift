import Basic
import TuistCore
import TuistGenerator

class MockGeneratorModelLoader: GeneratorModelLoading {
    private var projects = [String: (AbsolutePath) throws -> Project]()
    private var workspaces = [String: (AbsolutePath) throws -> Workspace]()

    private let basePath: AbsolutePath

    init(basePath: AbsolutePath) {
        self.basePath = basePath
    }

    // MARK: - GeneratorModelLoading

    func loadProject(at path: AbsolutePath) throws -> Project {
        return try projects[path.pathString]!(path)
    }

    func loadWorkspace(at path: AbsolutePath) throws -> Workspace {
        return try workspaces[path.pathString]!(path)
    }

    // MARK: - Mock

    func mockProject(_ path: String, loadClosure: @escaping (AbsolutePath) throws -> Project) {
        projects[basePath.appending(component: path).pathString] = loadClosure
    }

    func mockWorkspace(_ path: String = "", loadClosure: @escaping (AbsolutePath) throws -> Workspace) {
        workspaces[basePath.appending(component: path).pathString] = loadClosure
    }
}
