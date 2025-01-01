# typed: true
# frozen_string_literal: true

module Configurable
  module UsedBy
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Repository }

    DISABLED_KEY = "used_by.disabled".freeze
    SELECTION_KEY = "used_by.package_id".freeze

    def enable_used_by(actor:)
      return unless dependency_graph_enabled?
      return if used_by_enabled?

      config.delete(DISABLED_KEY, actor)
      GitHub.instrument("repository_used_by.enable", used_by_instrumentation_payload(actor))
    end

    def disable_used_by(actor:)
      return unless used_by_enabled?

      config.enable(DISABLED_KEY, actor)
      GitHub.instrument("repository_used_by.disable", used_by_instrumentation_payload(actor))
    end

    def used_by_enabled?
      return unless dependency_graph_enabled?
      return false unless public?

      !config.enabled?(DISABLED_KEY)
    end

    def set_used_by_package_id(actor:, package_id:)
      config.set(SELECTION_KEY, package_id, actor)
      GitHub.instrument("repository_used_by.set_package", used_by_instrumentation_payload(actor))
    end

    def used_by_package_id
      config.get(SELECTION_KEY)
    end

    def used_by_instrumentation_payload(user)
      payload = {
        user: user,
        repo: self,
      }

      if in_organization?
        payload[:org] = organization
      end

      payload
    end
  end
end
