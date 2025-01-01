# typed: true
# frozen_string_literal: true

module Configurable
  module CodespacesExpiryNotification
    extend T::Helpers
    extend Configurable::Async

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    class InvalidCodespacesExpiryNotificationType < ArgumentError; end

    KEY = "codespaces_expiry_notification"

    DISABLED = "disabled"
    ENABLED = "enabled"

    CONFIG_TYPES = [DISABLED, ENABLED]

    def codespaces_expiry_notification_enabled?
      config.get(KEY) != DISABLED
    end

    def update_codespaces_expiry_notification(codespaces_expiry_notification, force = false, actor:)
      codespaces_expiry_notification = DISABLED if codespaces_expiry_notification.blank?
      raise InvalidCodespacesExpiryNotificationType unless CONFIG_TYPES.include?(codespaces_expiry_notification)

      changed = config.set!(KEY, codespaces_expiry_notification, actor, force)
      return unless changed

      GitHub.dogstats.increment("codespaces_expiry_notification.updated")
    end
  end
end
