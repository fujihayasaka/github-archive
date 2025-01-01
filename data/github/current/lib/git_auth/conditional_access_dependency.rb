# typed: true
# frozen_string_literal: true

# Defines context specific plumbing to make Conditional Access Policy framework
# possible in GitAuth.
module GitAuth::ConditionalAccessDependency
  extend T::Helpers

  requires_ancestor { GitAuth::Authorization }

  # Full cap results
  def cap_results
    if use_authzd_oap_and_saml? && @cap_results_with_oap_and_saml
      outcomes = {}
      # { resource_id => [{ policy => outcome, ... }, { policy => message }]}
      @cap_results_with_oap_and_saml.each do |resource_id, results|
        outcomes[resource_id] = results.first
      end
      # { resource_id => { policy => outcome, ... } }
      outcomes
    else
      # { resource_id => { policy => outcome, ... } }
      @cap_results
    end
  end

  # CAP results and messages from authzd indexed by resource, including OAP and SAML policies
  # The resource for git auth is always a repository, so we can use the repo id
  # { resource_id => [{ policy => outcome }, { policy => message }]}
  def cap_results_with_oap_and_saml(resource)
    @cap_results_with_oap_and_saml ||= {}
    @cap_results_with_oap_and_saml[resource.id] ||= cap_enforcer.authzd_evaluate_conditional_access_policies(
      resource,
      policies: cap_enforcer.policies_plus_saml_and_oap,
      fail_fast: false,
      serving_prod_traffic: true)
  end

  def run_gitauth_oap_saml_cap_experiment?
    # cache FF result for whole check
    if @run_gitauth_oap_saml_cap_experiment.nil?
      @run_gitauth_oap_saml_cap_experiment = FeatureFlag.vexi.enabled?(:run_gitauth_oap_saml_cap_experiment, default: false)
    end
    @run_gitauth_oap_saml_cap_experiment
  end

  def use_authzd_oap_and_saml?
    # cache FF result for whole check
    if @use_authzd_oap_and_saml.nil?
      @use_authzd_oap_and_saml = FeatureFlag.vexi.enabled?(:use_authzd_oap_and_saml_gitauth, user, default: false)
    end
    @use_authzd_oap_and_saml
  end

  # Public: evaluates all conditional access policies over the repository
  #
  # Returns :ok if actor satisfies all policies, or a symbol representing an error code otherwise.
  def perform_conditional_access_checks(resource: repository, policies: cap_enforcer.conditional_access_policies, intel_fix: false)
    if use_authzd_oap_and_saml?
      perform_conditional_access_checks_candidate(resource:, intel_fix:)
    elsif run_gitauth_oap_saml_cap_experiment?
      # this experiment is enabled 100% of the time - we use the FF to control participation
      science_class = GitHub.multi_tenant_enterprise? && !Rails.env.test? ? ConditionalAccess::ProximaScientist : Scientist # rubocop:disable GitHub/DoNotBranchOnRailsEnv

      science_class.run "gitauth_oap_saml_cap_experiment" do |e|
        e.use do
          perform_conditional_access_checks_control(resource:, policies:)
        end
        e.try do
          perform_conditional_access_checks_candidate(resource:, intel_fix:)
        end
        e.compare do |control_result, candidate_result|
          matched = control_result == candidate_result
          # if we're using the custom ProximaScientist class, we won't have
          # the Scientist UI tooling with all of the context about mismatches
          # so for now we'll just log as much as we can here
          # the log automatically has the request ID, which can help us diagnose further if needed
          # Exception handling is part of the custom ProximaScientist class
          if !matched && GitHub.multi_tenant_enterprise?
            GitHub.logger.info(
              "Mismatch in authzd cap experiment - oauth application",
              "code.function" => "perform_conditional_access_checks",
              "authzd.cap.experiment_name" => "gitauth_oap_saml_cap_experiment",
              "authzd.cap.location" => "GitAuth",
              "authzd.cap.policies" => "#{policies.join(', ')}",
              "authzd.cap.control" => "#{control_result}",
              "authzd.cap.candidate" => "#{candidate_result}",
              "authzd.cap.resource.id" => resource&.try(:id) || 0,
              "authzd.cap.resource.type" => resource&.class&.name,
            )
          end
          matched
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

  def passes_saml_check_authzd_cap(resource)
    results, _messages = cap_results_with_oap_and_saml(resource)
    results[:saml] == :inapplicable || results[:saml] == :satisfied
  end

  def oap_result_authzd_cap(resource)
    results, messages, codes = cap_results_with_oap_and_saml(resource)
    [results[:oauth_application], messages[:oauth_application], codes[:oauth_application]]
  end

  private

  def perform_conditional_access_checks_control(resource: repository, policies: cap_enforcer.conditional_access_policies)
    results = cap_enforcer.evaluate_conditional_access_policies(resource, policies: policies, fail_fast: true)
    @cap_results ||= {}
    @cap_results[resource.id] ||= results
    unsatisfied_policy, _ = results.find { |_policy, result| result == :unsatisfied }
    return :ok if unsatisfied_policy.nil?

    error_code_for(unsatisfied_policy)
  end

  def perform_conditional_access_checks_candidate(resource: repository, intel_fix: false)
    results = if intel_fix
      results, _messages = cap_enforcer.authzd_evaluate_conditional_access_policies(
        resource,
        policies: [:ip_allowlist],
        fail_fast: false,
        serving_prod_traffic: true)
      if @cap_results_with_oap_and_saml.present?
        # To make it easier to identify mismatches with GotAuth, combine the results from the network root
        # with the previous :inapplicable results from the fork
        fork_id = @cap_results_with_oap_and_saml.keys.first
        fork_outcome = @cap_results_with_oap_and_saml[fork_id].first
        if fork_outcome[:ip_allowlist] == :inapplicable
          fork_outcome[:ip_allowlist] = results[:ip_allowlist]
        end
      end
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
