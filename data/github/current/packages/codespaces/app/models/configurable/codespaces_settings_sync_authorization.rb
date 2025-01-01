# typed: true
# frozen_string_literal: true

module Configurable
  module CodespacesSettingsSyncAuthorization
    extend T::Helpers
    extend Configurable::Async

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    class InvalidCodespaceSettingsSyncConfigType < ArgumentError; end

    KEY = "codespaces_settings_sync_authorization"

    DISABLED = "disabled"
    ENABLED = "enabled"

    CONFIG_TYPES = [DISABLED, ENABLED]

    def codespaces_settings_sync_authorization
      value = config.get(KEY)
      return DISABLED unless value
      value
    end

    def update_codespaces_settings_sync_authorization(codespaces_settings_sync_authorization, force = false, actor:)
      codespaces_settings_sync_authorization = DISABLED if codespaces_settings_sync_authorization.blank?
      raise InvalidCodespaceSettingsSyncConfigType unless CONFIG_TYPES.include?(codespaces_settings_sync_authorization)

      config.set!(KEY, codespaces_settings_sync_authorization, actor, force)
      CodespacesFlushSettingsSyncJob.perform_later(user: actor)
    end
  end
end
