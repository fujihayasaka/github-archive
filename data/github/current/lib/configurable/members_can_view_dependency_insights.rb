# typed: true
# frozen_string_literal: true

module Configurable
  module MembersCanViewDependencyInsights
    extend T::Helpers
    include Kernel

    requires_ancestor { Configurable }

    KEY = "disable_members_can_view_dependency_insights".freeze

    def allow_members_can_view_dependency_insights(force: false, actor:)
      changed = if force
        config.disable!(KEY, actor, force)
      else
        config.delete(KEY, actor)
      end
      return unless changed

      GitHub.dogstats.increment("members_can_view_dependency_insights.enable")
      GitHub.instrument("members_can_view_dependency_insights.enable", instrumentation_payload(actor))
    end

    def disallow_members_can_view_dependency_insights(force: false, actor:)
      changed = config.enable!(KEY, actor, force)
      return unless changed

      GitHub.dogstats.increment("members_can_view_dependency_insights.disable")
      GitHub.instrument("members_can_view_dependency_insights.disable", instrumentation_payload(actor))
    end

    def clear_members_can_view_dependency_insights(actor:)
      changed = config.delete(KEY, actor)
      return unless changed

      GitHub.dogstats.increment("members_can_view_dependency_insights.clear")
      GitHub.instrument("members_can_view_dependency_insights.clear", instrumentation_payload(actor))
    end

    def members_can_view_dependency_insights?
      !config.enabled?(KEY)
    end

    def members_can_view_dependency_insights_policy?
      !!config.final?(KEY)
    end

    private def instrumentation_payload(actor)
      payload = { user: actor }

      if self.is_a?(Organization)
        payload[:org] = self
        payload[:business] = self.business if self.business
      elsif self.is_a?(Business)
        payload[:business] = self
      end

      payload
    end
  end
end
