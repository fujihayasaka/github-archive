# typed: true
# frozen_string_literal: true

module Configurable
  module CodespaceDotfilesEnabled
    extend T::Helpers
    extend Configurable::Async

    requires_ancestor { Configurable }

    KEY = "codespace_dotfiles_enabled"

    def codespace_dotfiles_enabled?
      config.enabled?(KEY)
    end

    def enable_codespace_dotfiles(force = false, actor:)
      config.enable!(KEY, actor, force)
      GitHub.dogstats.increment("codespace_dotfiles_enabled.enabled")
    end

    def disable_codespace_dotfiles(force = false, actor:)
      config.disable!(KEY, actor, force)
      GitHub.dogstats.increment("codespace_dotfiles_enabled.disabled")
    end
  end
end
