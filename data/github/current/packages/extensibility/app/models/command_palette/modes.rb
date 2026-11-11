# typed: true
# frozen_string_literal: true

module CommandPalette
  class Modes
    MODES = {
      global_references: {
        character: "#",
        placeholder: "Search issues and pull requests",
        scope_types: [:global]
      },
      owner_repo_references: {
        character: "#",
        placeholder: "Search issues, pull requests, discussions, and projects",
        scope_types: [:owner, :repository]
      },
      projects: {
        character: "!",
        placeholder: "Search projects",
        scope_types: [:owner, :repository]
      },
      global_jump_to: {
        character: "@",
        placeholder: "Search or jump to a user, organization, or repository",
        scope_types: [:global]
      },
      owner_jump_to: {
        character: "@",
        placeholder: "Search or jump to a repository",
        scope_types: [:owner]
      },
      files: {
        character: "/",
        placeholder: "Search files",
        scope_types: [:repository]
      },
      help: {
        character: "?",
        placeholder: "",
        scope_types: [] # available in all scopes
      },
      commands: {
        character: ">",
        placeholder: "Run a command",
        scope_types: [] # available in all scopes
      },
      modeless_global: {
        character: "",
        placeholder: "Search or jump to...",
        scope_types: [:global],
      },
      modeless_owner: {
        character: "",
        placeholder: "Search or jump to...",
        scope_types: [:owner],
      },
      default: {
        character: "",
        placeholder: "Search or jump to...",
        scope_types: [:global, :owner, :repository],
      },
    }

    REGISTERED_MODES = MODES.keys

    def self.all
      MODES.values.map { |options| Mode.new(**options) }
    end

    def self.all_except_default
      MODES.reject do |key, _options|
        key == :default
      end.map do |_key, options|
        Mode.new(**options)
      end
    end

    def self.default
      Mode.new(**MODES[:default])
    end

    def self.mode(key)
      options = MODES[key]
      return unless options
      Mode.new(**options)
    end
  end
end
