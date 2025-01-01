# typed: true
# frozen_string_literal: true

# Defines context specific plumbing to make Conditional Access Policy framework
# possible in GitAuth.
module GitAuth::ConditionalAccessDependency
  extend T::Helpers

  requires_ancestor { GitAuth::Authorization }

  # Full cap results
  attr_reader :cap_results

  # CAP results from authzd indexed by resource, including OAP and SAML policies
  def cap_results_with_oap_and_saml(resource)
    @cap_results_with_oap_and_saml ||= {}
    @cap_results_with_oap_and_saml[resource] ||= cap_enforcer.authzd_evaluate_conditional_access_policies(
      resource,
      policies: cap_enforcer.policies_plus_saml_and_oap,
      fail_fast: false,
      serving_prod_traffic: false)
  end

  def run_gitauth_oap_saml_cap_experiment?
    # cache FF result for whole check
    if @run_gitauth_oap_saml_cap_experiment.nil?
      @run_gitauth_oap_saml_cap_experiment = GitHub.flipper[:run_gitauth_oap_saml_cap_experiment].enabled?
    end
    @run_gitauth_oap_saml_cap_experiment
  end

  # Public: evaluates all conditional access policies over the repository
  #
  # Returns :ok if actor satisfies all policies, or a symbol representing an error code otherwise.
  def perform_conditional_access_checks(resource: repository, policies: cap_enforcer.conditional_access_policies, intel_fix: false)
    if run_gitauth_oap_saml_cap_experiment?
      # this experiment is enabled 100% of the time - we use the FF to control participation
      Scientist.run "gitauth_oap_saml_cap_experiment" do |e|
        e.use do
          perform_conditional_access_checks_control(resource:, policies:)
        end
        e.try do
          perform_conditional_access_checks_candidate(resource:, intel_fix:)
        end
      end
    else
      perform_conditional_access_checks_control(resource:, policies:)
    end
  end

  def saml_result_authzd_cap(resource)
    results, _messages = cap_results_with_oap_and_saml(resource)
    results[:saml]
  end

  def oap_result_authzd_cap(resource)
    results, messages = cap_results_with_oap_and_saml(resource)
    [results[:oauth_application], messages[:oauth_application]]
  end

  private

  def perform_conditional_access_checks_control(resource: repository, policies: cap_enforcer.conditional_access_policies)
    @cap_results = cap_enforcer.evaluate_conditional_access_policies(resource, policies: policies, fail_fast: true)
    unsatisfied_policy, _ = @cap_results.find { |_policy, result| result == :unsatisfied }
    return :ok if unsatisfied_policy.nil?

    error_code_for(unsatisfied_policy)
  end

  def perform_conditional_access_checks_candidate(resource: repository, intel_fix: false)
    results = if intel_fix
      results, _messages = cap_enforcer.authzd_evaluate_conditional_access_policies(
        resource,
        policies: [:ip_allowlist],
        fail_fast: false,
        serving_prod_traffic: false)
      results
    else
      results, _messages = cap_results_with_oap_and_saml(resource)
      results
    end

    unsatisfied_policy, _ = results
      .reject { |policy, _result| policy == :oauth_application || policy == :saml }
      .find { |_policy, result| result == :unsatisfied }

    return :ok if unsatisfied_policy.nil?

    error_code_for(unsatisfied_policy)
  end

  # rubocop:disable GitHub/DoNotInstantiatePlatformObjects
  def cap_enforcer
    @conditional_access_enforcer ||= ConditionalAccess::CapGitAuth::Enforcer.new(self)
  end
  # rubocop:enable GitHub/DoNotInstantiatePlatformObjects

  # Translates CAP policy identifiers into GitAuth error code
  def error_code_for(policy)
    case policy
    when :ip_allowlist
      :not_ip_allowlisted
    when :two_factor
      :two_factor_noncompliant
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
