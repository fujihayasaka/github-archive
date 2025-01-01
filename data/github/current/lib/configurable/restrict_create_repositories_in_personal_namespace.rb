# typed: false
# frozen_string_literal: true

module Configurable
  module RestrictCreateRepositoriesInPersonalNamespace
    KEY = "enable_restrict_create_repository_in_personal_namespace".freeze


    def enable_restrict_create_repository_in_personal_namespace(force: false, actor:)
      return if basic_seats_plan_business?
      changed = if force
        config.enable!(KEY, actor, force)
      else
        config.enable(KEY, actor)
      end
      return unless changed

      GitHub.dogstats.increment("create_repository_in_personal_namespace_enable")
      GitHub.instrument("create_repository_in_personal_namespace_enabled", instrumentation_payload(actor))
    end

    def disable_restrict_create_repository_in_personal_namespace(force: false, actor:)
      return if basic_seats_plan_business?
      changed = config.disable!(KEY, actor, force)
      return unless changed
      GitHub.dogstats.increment("create_repository_in_personal_namespace_disable")
      GitHub.instrument("create_repository_in_personal_namespace_disabled", instrumentation_payload(actor))
    end

    def restrict_create_repository_in_personal_namespace_enabled?
      return true if basic_seats_plan_business?
      config.enabled?(KEY)
    end

    private def basic_seats_plan_business?
      if self.is_a?(Business)
        T.bind(self, Business)
        return true if self.seats_plan_basic?
      end
      false
    end

    # Returns: hash of parameters for instrumentation
    private def instrumentation_payload(actor)
      payload = { user: actor }

      if self.is_a?(Business)
        payload[:business] = self
      end

      payload
    end
  end
end
