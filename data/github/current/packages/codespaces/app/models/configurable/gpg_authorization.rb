# typed: true
# frozen_string_literal: true

module Configurable
  module GpgAuthorization
    extend T::Helpers
    extend Configurable::Async

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    class InvalidCodespaceGPGConfigType < ArgumentError; end

    KEY = "gpg_authorization"

    DISABLED              = "disabled"
    ENABLED               = "enabled"
    ALL_REPOSITORIES      = "all_repositories"
    SELECTED_REPOSITORIES = "selected_repositories"

    CONFIG_TYPES = [DISABLED, ENABLED, ALL_REPOSITORIES, SELECTED_REPOSITORIES]

    def gpg_authorization
      config.get(KEY) == DISABLED ? DISABLED : ENABLED
    end

    def update_gpg_authorization(gpg_authorization, force = false, actor:)
      gpg_authorization = DISABLED if gpg_authorization.blank?
      raise InvalidCodespaceGPGConfigType unless CONFIG_TYPES.include?(gpg_authorization)

      changed = config.set!(KEY, gpg_authorization, actor, force)
      return unless changed

      GitHub.dogstats.increment("gpg_authorization.updated")
    end
  end
end
