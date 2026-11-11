# typed: true
# frozen_string_literal: true

module Configurable
  module RemoveUserAccountsWhenRemovingLastOrgMembership
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }

    KEY = "remove_user_accounts_when_removing_last_org_membership".freeze

    sig { params(actor: User, remove_existing_unaffiliated_users: T::Boolean, users_removed_count: T.nilable(Integer)).void }
    def enable_remove_user_accounts_when_removing_last_org_membership(actor:, remove_existing_unaffiliated_users: false, users_removed_count: nil)
      old_value = remove_user_accounts_when_removing_last_org_membership_setting_enabled?
      changed = config.enable(KEY, actor)
      return unless changed

      new_value = true

      GitHub.dogstats.increment("remove_user_accounts_when_removing_last_org_membership_enable")
      GitHub.instrument("remove_user_accounts_when_removing_last_org_membership_enabled", instrumentation_payload(actor))

      instrument_unaffiliated_users_policy_update(
        actor: actor,
        old_value: old_value,
        new_value: new_value,
        remove_existing_unaffiliated_users: remove_existing_unaffiliated_users,
        users_removed_count: users_removed_count
      )
    end

    sig { params(actor: User).void }
    def disable_remove_user_accounts_when_removing_last_org_membership(actor:)
      old_value = remove_user_accounts_when_removing_last_org_membership_setting_enabled?
      changed = config.disable(KEY, actor)
      return unless changed

      new_value = false

      GitHub.dogstats.increment("remove_user_accounts_when_removing_last_org_membership_disable")
      GitHub.instrument("remove_user_accounts_when_removing_last_org_membership_disabled", instrumentation_payload(actor))

      instrument_unaffiliated_users_policy_update(actor: actor, old_value: old_value, new_value: new_value)
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

    sig { params(actor: User, old_value: T::Boolean, new_value: T::Boolean, remove_existing_unaffiliated_users: T::Boolean, users_removed_count: T.nilable(Integer)).void }
    private def instrument_unaffiliated_users_policy_update(actor:, old_value:, new_value:, remove_existing_unaffiliated_users: false, users_removed_count: nil)
      return unless self.is_a?(Business)

      policy_old_value = old_value ? "remove_from_enterprise" : "stay_in_enterprise"
      policy_new_value = new_value ? "remove_from_enterprise" : "stay_in_enterprise"

      payload = {
        actor: actor,
        business: self,
        old_value: policy_old_value,
        new_value: policy_new_value,
        remove_existing_unaffiliated_users: remove_existing_unaffiliated_users,
        users_removed_count: users_removed_count,
      }

      GitHub.instrument("business.update_unaffiliated_users_policy", payload)
    end
  end
end
