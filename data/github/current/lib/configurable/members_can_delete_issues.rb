# typed: true
# frozen_string_literal: true

module Configurable
  module MembersCanDeleteIssues
    extend T::Helpers
    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    KEY = "enable_members_can_delete_issues".freeze

    def allow_members_can_delete_issues(force: false, actor:)
      changed = if force
        config.enable!(KEY, actor, force)
      else
        config.enable(KEY, actor)
      end
      return unless changed

      GitHub.dogstats.increment("members_can_delete_issues.enable")
      GitHub.instrument("issues.deletes_enabled", instrumentation_payload(actor))
    end

    def disallow_members_can_delete_issues(force: false, actor:)
      changed = config.disable!(KEY, actor, force)
      return unless changed

      GitHub.dogstats.increment("members_can_delete_issues.disable")
      GitHub.instrument("issues.deletes_disabled", instrumentation_payload(actor))
    end

    def clear_members_can_delete_issues(actor:)
      changed = config.delete(KEY, actor)
      return unless changed

      GitHub.dogstats.increment("members_can_delete_issues.clear")
      GitHub.instrument("issues.deletes_policy_cleared", instrumentation_payload(actor))
    end

    def members_can_delete_issues?
      config.enabled?(KEY)
    end

    def members_can_delete_issues_policy?
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
