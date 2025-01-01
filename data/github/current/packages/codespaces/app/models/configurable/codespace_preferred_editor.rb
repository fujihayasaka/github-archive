# typed: true
# frozen_string_literal: true

module Configurable
  module CodespacePreferredEditor
    extend T::Helpers
    extend Configurable::Async

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    class InvalidCodespaceEditor < ArgumentError; end

    KEY = "codespace_preferred_editor"

    def codespace_preferred_editor
      config.get(KEY) || Codespaces::Settings::PREFERRED_EDITOR_VSCODE_WEB
    end

    def update_codespace_preferred_editor(editor, force = false, actor:)
      raise InvalidCodespaceEditor unless Codespaces::Settings::EDITORS.include?(editor)

      changed = config.set!(KEY, editor, actor, force)
      return unless changed

      GitHub.dogstats.increment("codespace_preferred_editor.updated")
    end
  end
end
