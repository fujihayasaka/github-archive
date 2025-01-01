# typed: true
# frozen_string_literal: true

module Configurable
  module CodespacesVscodeChannel
    extend Configurable::Async
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    class InvalidCodespacesVscodeChannel < ArgumentError; end

    KEY = "codespace_vscode_channel"

    def codespace_vscode_channel
      config.get(KEY) || Codespaces::Settings::DEFAULT_VSCODE_CHANNEL
    end

    def update_codespace_vscode_channel(setting, force = false, actor:)
      raise InvalidCodespacesVscodeChannel unless Codespaces::Settings::VSCODE_CHANNELS.include?(setting)

      changed = config.set!(KEY, setting, actor, force)
      return unless changed

      GitHub.dogstats.increment("codespace_vscode_channel.updated")
    end
  end
end
