# typed: true
# frozen_string_literal: true

# Defines context specific plumbing to make Conditional Access Policy framework
# possible in GitAuth.
module GitAuth::ConditionalAccessDependency
  extend T::Helpers

  requires_ancestor { GitAuth::Authorization }

  # Public: evaluates all conditional access policies over the repository
  #
  # Returns :ok if actor satisfies all policies, or a symbol representing an error code otherwise.
  def perform_conditional_access_checks(resource: repository, policies: cap_enforcer.conditional_access_policies)
    results = cap_enforcer.evaluate_conditional_access_policies(resource, policies: policies, fail_fast: true)
    unsatisfied_policy, _ = results.find { |_policy, result| result == :unsatisfied }
    return :ok if unsatisfied_policy.nil?

    error_code_for(unsatisfied_policy)
  end

  private

  def cap_enforcer
    @conditional_access_enforcer ||= ConditionalAccess::GitAuth::Enforcer.new(self)
  end

  # Translates CAP policy identifiers into GitAuth error code
  def error_code_for(policy)
    case policy
    when :ip_allowlist
      :not_ip_allowlisted
    when :two_factor
      :two_factor_missing
    when :external_conditional_access_policy
      :external_conditional_access_policy_failed
    when :legacy_personal_access_tokens
      :legacy_personal_access_tokens_forbidden
    when :personal_access_tokens
      :personal_access_tokens_forbidden
    when :personal_access_tokens_expiration_limit
      :personal_access_tokens_expiration_limit_exceeded
    else
      :access_denied_to_user
    end
  end
end
