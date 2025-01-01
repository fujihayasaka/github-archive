# typed: true
# frozen_string_literal: true

module ConditionalAccess
  class AuthzdEnforcer < Enforcer
    private

    # overrides Enforcer#do_evaluate_conditional_access_policies to use authzd for policy evaluation
    def do_evaluate_conditional_access_policies(resource, policies: conditional_access_policies, fail_fast: false)
      authzd_evaluate_conditional_access_policies(resource, policies:, fail_fast:)
    end
  end
end
