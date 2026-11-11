# typed: true
# frozen_string_literal: true

module Configurable
  module RemoveUserAccountsWhenRemovingLastOrgMembership
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }

    KEY = "remove_user_accounts_when_removing_last_org_membership".freeze

    sig { params(actor: User).void }
    def enable_remove_user_accounts_when_removing_last_org_membership(actor:)
      changed = config.enable(KEY, actor)
      return unless changed

      GitHub.dogstats.increment("remove_user_accounts_when_removing_last_org_membership_enable")
      GitHub.instrument("remove_user_accounts_when_removing_last_org_membership_enabled", instrumentation_payload(actor))
    end

    sig { params(actor: User).void }
    def disable_remove_user_accounts_when_removing_last_org_membership(actor:)
      changed = config.disable(KEY, actor)
      return unless changed

      GitHub.dogstats.increment("remove_user_accounts_when_removing_last_org_membership_disable")
      GitHub.instrument("remove_user_accounts_when_removing_last_org_membership_disabled", instrumentation_payload(actor))
    end

    sig { returns(T::Boolean) }
    def remove_user_accounts_when_removing_last_org_membership_setting_enabled?
      config.enabled?(KEY)
    end

    sig { params(actor: User).returns(T::Hash[String, T.untyped]) }
    private def instrumentation_payload(actor)
      payload = { user: actor }

      if self.is_a?(Business)
        payload[:business] = self
      end

      payload
    end
  end
end
