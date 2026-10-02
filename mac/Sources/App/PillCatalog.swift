import Foundation

// MARK: - Pill category

enum PillCategory: String, CaseIterable {
    case workspace
    case agent
    case ai
    case service

    var title: String {
        switch self {
        case .workspace: return "Where you code"
        case .agent:     return "Agents"
        case .ai:        return "AI for the chat"
        case .service:   return "Services"
        }
    }
}

// MARK: - Pill definition

struct PillDefinition {
    let id:         String
    let name:       String
    let color:      String
    let category:   PillCategory
    /// Label shown next to the task name in the idle card header.
    let subtitle:   String
    let source:     AgentSource
    var comingSoon: Bool = false
    var githubOnly: Bool = false

    /// Label shown in the active-session card header (workspace/agent pills only).
    var sessionSubtitle: String {
        id == "integration_claude" ? "Blue Agent" : "Agent"
    }
}

// MARK: - Catalog

enum PillCatalog {
    // All declared pills in display order.
    // BlueBot shows one pill: Blue Agent. It keeps the id "integration_claude"
    // because that id is the app's always-on main pill (loaded first, never
    // removed — see AppState.loadIntegrationTasks); the id is internal only.
    static let all: [PillDefinition] = [
        .init(id: "integration_claude",  name: "Blue Agent",  color: "#4FC3F7",
              category: .workspace, subtitle: "Alerts",       source: .n8n),
    ]

    /// Pills available in the current build target.
    static var available: [PillDefinition] {
        #if APPSTORE
        all.filter { !$0.githubOnly }
        #else
        all
        #endif
    }

    /// Default ID for the always-on main workspace pill.
    static let defaultMainPillId = "integration_claude"

    /// Looks up a definition by task ID (nil if not in catalog).
    static func definition(for id: String) -> PillDefinition? {
        all.first { $0.id == id }
    }
}
