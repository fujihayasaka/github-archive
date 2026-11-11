# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Concerns
      module DirectOrgBillingAccess
        include GitHub::ResilienceMixin

        sig { params(user: T.any(Copilot::User, Copilot::Public::User), dependent_policy_column: T.nilable(Symbol)).returns(T::Boolean) }
        def has_access_via_direct_org_billing?(user, dependent_policy_column: nil)
          return false if user.has_copilot_access?

          org_ids = user.user_object.organization_ids
          return false if org_ids.empty?

          conditions = {
            configurable_id: org_ids,
            configurable_type: "Organization",
            ccr_direct_org_billing: "enabled",
          }
          conditions[dependent_policy_column] = "enabled" if dependent_policy_column

          with_database_error_fallback(fallback: false) do
            Copilot::Configuration.exists?(conditions)
          end
        end
      end
    end
  end
end
