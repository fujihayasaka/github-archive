# typed: true
# frozen_string_literal: true

class ApplySecurityConfigurationToRepositoryJob < ApplicationJob
  include GitHub::Memoizer
  include SecretScanning::Features::FeatureFlagHelper
  include Settings::SecurityProducts::BlockedSettingsHelper

  queue_as :security_configurations

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  Error = Class.new(StandardError)
  RetryableError = Class.new(Error)
  FatalError = Class.new(Error)
  RepositoryNotFound = Class.new(RetryableError)
  ActorNotFound = Class.new(RetryableError)
  SecurityConfigurationNotFound = Class.new(RetryableError)
  RepositorySecurityConfigurationNotFound = Class.new(RetryableError)
  SecurityConfigurationOwnerMismatch = Class.new(FatalError)
  RepositoryDeleted = Class.new(FatalError)
  RepositoryArchived = Class.new(FatalError)

  # For cases where we can reasonably expect a different result when retrying
  # (i.e. possible DB lag).
  EXCEPTIONS = [RetryableError, AdvancedSecurityLicense::TurboghasError, CodeScanning::AutoCodeqlError]
  retry_on *T.unsafe(EXCEPTIONS), wait: :polynomially_longer, attempts: 5 do |job, error|
    job.handle_permanent_job_failure(error)
    raise error
  end

  # For cases where we don't expect a retry to result in a different result,
  # discard so that we mark the job as failed.
  discard_on FatalError

  before_enqueue do |job|
    next if job.applying_to_new_repo?
    next if job.executions != 0 # Skip this logic if we're enqueueing due to a retry:

    update_types(security_configuration).each { |update_type| repo_counter&.increment(update_type) }
  end

  after_perform :mark_job_as_completed

  def handle_permanent_job_failure(error)
    mark_job_as_completed
    mark_repository_security_configuration_as_failed(error)
  end

  def mark_job_as_completed
    # If the reason this job was enqueued was repo creation, we can skip progress updates:
    return if applying_to_new_repo?

    update_types(security_configuration).each { |update_type| repo_counter&.decrement(update_type) }

    update_job_progress_tracker
  end

  def mark_repository_security_configuration_as_failed(error)
    reason = T.must(error.class.name).demodulize.underscore

    RepositorySecurityConfiguration.throttle_writes_with_retry do
      repository_security_configuration&.update!(state: :failed, failure_reason: reason) if repository_security_configuration&.attaching?
    end
  end

  after_discard do |job, error|
    job.handle_permanent_job_failure(error)
  end

  UNPREVENTABLE_ERROR_REASONS = T.let([
    # Dependency Graph Automatic submission
    "Automatic dependency submission can only be enabled if Actions is enabled. GitHub Actions is disabled on this repository, please enable it.",
    "Automatic dependency submission can only be enabled if runners with label #{SecurityProduct::DependencyGraphAutosubmitAction::ACTIONS_RUNNER_LABEL} are assigned to this repository.",
    "Automatic dependency submission can only be enabled if Dependency graph is enabled. Please enable Dependency graph for this repository.",
    "Automatic dependency submission is not available.",
    # Code Scanning AutoCodeql
    "Code scanning default setup can only be enabled if Actions is enabled. GitHub Actions is not enabled on this instance, please ask your instance administrator to configure Actions.",
    "Code scanning default setup can only be enabled if Actions is enabled. GitHub Actions is not enabled on this instance, please configure Actions.",
    "Code scanning default setup can only be enabled if Actions is enabled. GitHub Actions is disabled on this repostiory by an enterprise or organization policy. Please ask your organization administrator to enable Actions.",
    "Code scanning default setup can only be enabled if Actions is enabled. GitHub Actions is disabled on this repository, please enable it.",
    "Code scanning default setup can only be enabled if Actions is enabled. GitHub Actions is disabled by default on this repository because it is a fork, please enable it.",
    "GitHub Actions policy is limiting the use of some required actions. To use code scanning default setup, allow actions from `actions/*` and `github/codeql-action/*`.",
    "Code scanning default setup can only be enabled if runners with label code-scanning are assigned to this repository.",
    "Code scanning default setup for Swift can only be enabled if runners with both code-scanning and macOS labels are assigned to this repository.",
    "Code scanning default setup can only be enabled if no manual workflow is configured.",
    # Advanced security
    "Advanced security has not been purchased.",
    "Enabling advanced security is restricted by a policy.",
    "Enabling advanced security would exceed seat allowance."
  ].freeze, T::Array[String])

  sig do
    params(
      actor_id: Integer,
      repository_id: Integer,
      security_configuration_id: Integer,
      override_params: T::Hash[Symbol, String],
      reason: T.nilable(Symbol),
      skip_ghas_features: T::Boolean,
    ).void
  end
  def perform(actor_id:, repository_id:, security_configuration_id:, override_params: {}, reason: nil, skip_ghas_features: false)
    GitHub.logger.info("Beginning job")

    check_preconditions!

    # if any of these are nil, the skip_reason guard above will prevent us from reaching this
    # so we can safely unwrap these optionals
    repository = T.must_because(self.repository) { "checked above" }
    actor = T.must_because(self.actor) { "checked above" }
    security_configuration = T.must_because(self.security_configuration) { "checked above" }
    repository_security_configuration = T.must_because(self.repository_security_configuration) { "checked above" }

    # If the job was enqueued with the intention of skipping GHAS features, validate if we'd really like to:
    if skip_ghas_features
      skip_ghas_features, skip_ghas_features_reason = validate_skipping_ghas_features?
      GitHub.logger.info("Will skip enabling GHAS features, reason: #{skip_ghas_features_reason}")
    end

    # Because we are making changes to repository security settings based on a configuration update, we need to let
    # the toggle services method know. This will allow us to skip some checks pertaining to configuration enforcement
    override_params.merge!(enablement_action: "security_configuration_enablement")

    if applying_to_new_repo?
      override_params.merge!(is_repo_creation: true)
    end

    params = toggle_services_params(
      repository,
      security_configuration,
      override_params,
      skip_ghas_features,
    )

    GitHub.logger.info("Calling SecurityProduct::ServiceManager with params: #{params.inspect}")

    result = ::Repository.throttle_writes_with_retry do
      SecurityProduct::ServiceManager
        .new(repository)
        .toggle_services_with_form_inputs(
          actor,
          params:,
          use_human_readable_error: true,
          skip_instrumentation: applying_to_new_repo?
        )
    end

    error = T.let(result.error&.to_s, T.nilable(String))
    state =
      if error
        :failed
      elsif security_configuration.enforced?(T.must(repository.owner))
        :enforced
      else
        :attached
      end

    GitHub.logger.info("SecurityProduct::ServiceManager result: #{result.to_a.inspect}")
    GitHub.dogstats.increment("apply_security_configuration_to_repository_job.result", tags: ["state:#{state}"])

    if repository.archived?
      GitHub.dogstats.increment("apply_security_configuration_to_repository_job.on_archived_repository", tags: ["state:#{state}"])
    end

    if error
      preventable = !UNPREVENTABLE_ERROR_REASONS.include?(error)
      GitHub.logger.error("apply_security_configuration_to_repository_job.service_manager_error": error,
        "apply_security_configuration_to_repository_job.service_manager_error_preventable": preventable)
      GitHub.dogstats.increment("apply_security_configuration_to_repository_job.error", tags: ["preventable:#{preventable}", "error:#{error}"])
    end

    if skip_ghas_features && security_configuration.enables_ghas_features?
      if [:seat_allowance_exceeded, :repo_consumes_additional_license].include?(skip_ghas_features_reason)
        skip_ghas_features_reason = :advanced_security_would_exceed_limit
      end

      if skip_ghas_features_reason
        state = :failed
        error = SecurityProduct::AdvancedSecurity.error_to_message(skip_ghas_features_reason)
      end
    end

    RepositorySecurityConfiguration.throttle_writes_with_retry do
      repository_security_configuration.update!(state: state, failure_reason: error)
    end

  rescue ActiveRecord::RecordNotFound => e
    # sometimes the repository is deleted during the middle of our job run
    # this checks for that exception and raises a RepositoryDeleted exception to discard the job
    raise(repository_deleted? ? RepositoryDeleted : e)
  end

  sig do
    params(
      repository: ::Repository,
      security_configuration: SecurityConfiguration,
      override_params: T::Hash[Symbol, String],
      skip_ghas_features: T::Boolean,
    ).returns(T::Hash[Symbol, T.any(String, T::Boolean)])
  end
  def toggle_services_params(repository, security_configuration, override_params, skip_ghas_features)
    installation_manager = SecurityProductsEnablement::SecurityProductsManager.new

    feature_params = {
      private_vulnerability_reporting_enabled: !installation_manager.private_vulnerability_reporting_enabled? ? "not_set" : security_configuration.private_vulnerability_reporting,
      dependency_graph_enabled: !installation_manager.dependency_graph_enabled? ? "not_set" : security_configuration.dependency_graph,
      vulnerability_alerts_enabled: !installation_manager.dependabot_alerts_enabled? ? "not_set" : security_configuration.dependabot_alerts,
      vulnerability_updates_enabled: !installation_manager.dependabot_security_updates_enabled? ? "not_set" : security_configuration.dependabot_security_updates,
      auto_codeql_enabled: !installation_manager.code_scanning_default_setup_enabled? ? "not_set" : security_configuration.code_scanning,
      token_scanning_enabled: !installation_manager.secret_scanning_enabled? ? "not_set" : security_configuration.secret_scanning,
      token_scanning_push_protection_enabled: !installation_manager.secret_scanning_enabled? ? "not_set" : security_configuration.secret_scanning_push_protection,
      token_scanning_delegated_bypass_enabled: !installation_manager.secret_scanning_enabled? ? "not_set" : security_configuration.secret_scanning_delegated_bypass,
      token_scanning_lower_confidence_patterns_enabled: !installation_manager.secret_scanning_enabled? ? "not_set" : security_configuration.secret_scanning_non_provider_patterns
    }

    if T.must(repository.owner).feature_enabled?(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS)
      feature_params[:token_scanning_validity_checks_enabled] = !installation_manager.secret_scanning_enabled? ? "not_set" : security_configuration.secret_scanning_validity_checks
    end

    if SecurityProduct::DependencyGraphAutosubmitAction.new(repository).available_in_security_configuration?
      feature_params[:dependency_graph_autosubmit_action_enabled] =
        security_configuration.dependency_graph_autosubmit_action
    end

    params = { skip_if_enabled: true, skip_if_disabled: true, ignore_import: true }

    feature_params.each do |key, value|
      next if value == "not_set"
      next if key == :private_vulnerability_reporting_enabled && repository.private? # PVR is only available to public repos
      next if key == :dependency_graph_enabled && repository.public? # DG cannot be disabled on public repos so we ignore it and apply the rest of the config settings

      # If we're skipping GHAS features for this configuration only include free features in params:
      if skip_ghas_features
        service_manager_key = key.to_s.gsub(/_enabled$/, "").to_sym
        next unless service_manager_key.in?(SecurityProduct::ServiceManager::NON_GHAS_SERVICES.keys)
      end

      params[key] = (value == "enabled") ? "1" : "0"
    end

    if (GitHub.enterprise? || repository.private?) && !skip_ghas_features
      if GitHub.enterprise? && !T.must(repository.owner).advanced_security_purchased?
        params[:advanced_security_enabled] = "0"
      else
        params[:advanced_security_enabled] = security_configuration.enable_ghas ? "1" : "0"
      end
    end

    if params[:auto_codeql_enabled] == "1"
      params[:fail_on_manual_workflow] = "1"
      code_scanning_opts = CodeScanning::AutoCodeql::Options.new_from_hash(security_configuration.code_scanning_options)
      unless code_scanning_opts.not_set?
        params[:auto_codeql_runner_type] = code_scanning_opts.runner_type
        params[:auto_codeql_runner_label] = code_scanning_opts.runner_label
      end
    end

    # If autosubmit is enabled, map peristed options unto the respective SecurityProduct::SettingsForm param
    if params[:dependency_graph_autosubmit_action_enabled] == "1"
      dgas_options = SecurityProduct::DependencyGraphAutosubmitAction::Options.new_from_hash(
        security_configuration.dependency_graph_autosubmit_action_options
      )

      params[:dependency_graph_autosubmit_action_use_labeled_runners] = dgas_options.labeled_runners ? "1" : "0"
    end

    # If it is the GH recommended config and Dependabot alerts are enabled, enable the default Dependabot rule
    if params[:vulnerability_alerts_enabled] == "1" && security_configuration.is_github_recommended_configuration?
      params[:dependabot_alerts_global_rule_enabled] = "1"
    end

    # If security updates are being enabled, we also enable grouped security updates if it's selected in the global settings page
    if params[:vulnerability_updates_enabled] == "1" && T.must(repository.owner).vulnerability_updates_grouping_enabled_for_new_repos?
      params[:vulnerability_updates_grouping_enabled] = "1"
    end

    if repository.archived?
      # An archived repository can only have the following features enabled:
      # - Secret Scanning
      # - Secret Scanning Non provider patterns
      # - Secret Scanning Validity checks

      # If feature is a Secret scanning (AKA token scanning in code) one, maintain its enablement value from the security configuration
      # Otherwise, set it to disabled
      params.each do |key, value|
        params[key] = key.to_s.include?("token_scanning") ? value : "0"
      end

      # Secret Scanning Push protection is not available for archived repos so we manually set it to disabled
      # Secret Scanning Delegated bypass, which depends on push protection, should also be disabled
      params[:token_scanning_push_protection_enabled] = "0"
      params[:token_scanning_delegated_bypass_enabled] = "0"
    end

    if !SecretScanning::Features::AdvancedSecurityHelper.advanced_security_available?(repository)
      params.delete(:token_scanning_lower_confidence_patterns_enabled)
      params.delete(:token_scanning_validity_checks_enabled)
    end

    params.merge!(repository.default_settings_for_features_not_in_security_configuration) if applying_to_new_repo?
    params.merge(override_params)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def logging_context
    owner = repository&.owner
    owner_tag_prefix = owner&.organization? ? "gh.org" : "gh.user"

    tags = {
      "gh.repo.id": arguments.dig(0, :repository_id),
      "gh.repo.name": repository&.name,
      "#{owner_tag_prefix}.id": repository&.owner_id,
      "#{owner_tag_prefix}.login": owner&.display_login,
      "gh.enduser.id": arguments.dig(0, :actor_id),
      "gh.enduser.login": actor&.display_login,
      "gh.security_configuration.id": arguments.dig(0, :security_configuration_id),
      "gh.security_configuration.apply_repo_job.override_params": arguments.dig(0, :override_params),
      "gh.security_configuration.apply_repo_job.reason": arguments.dig(0, :reason),
      "gh.security_configuration.apply_repo_job.skip_ghas_features": arguments.dig(0, :skip_ghas_features),
      "code.namespace": self.class.name,
    }

    super.merge(tags)
  end

  sig { returns(T.nilable(::Repository)) }
  memoize def repository
    repository_id = arguments.dig(0, :repository_id)
    return unless repository_id
    Repositories::Public.find_active(repository_id)
  end

  sig { returns(T.nilable(T::Boolean)) }
  def repository_deleted?
    repository_id = arguments.dig(0, :repository_id)
    return unless repository_id
    Repositories::Public.is_deleted?(repository_id)
  end

  sig { returns(T.nilable(User)) }
  memoize def actor
    actor_id = arguments.dig(0, :actor_id)
    return unless actor_id
    User.find_by(id: actor_id)
  end

  sig { returns(T.nilable(SecurityConfiguration)) }
  memoize def security_configuration
    security_configuration_id = arguments.dig(0, :security_configuration_id)
    return unless security_configuration_id
    SecurityConfiguration.find_by(id: security_configuration_id)
  end

  sig { returns(T.nilable(RepositorySecurityConfiguration)) }
  memoize def repository_security_configuration
    return unless repository.present? && security_configuration.present?
    RepositorySecurityConfiguration.find_by(
      repository_id: T.must(repository).id,
      security_configuration_id: T.must(security_configuration).id
    )
  end

  sig { void }
  def update_job_progress_tracker
    owner = repository&.owner
    return unless owner&.organization?

    remaining_jobs = job_progress_tracker.decrement_jobs
    return unless remaining_jobs.zero?

    job_progress_tracker.finish

    if arguments.dig(0, :override_params, :skip_backfill_request).present?
      # The pop_repository_ids method returns nil when there are no more
      # repository IDs to pop off of the Redis set.
      while repository_ids = job_progress_tracker.pop_repository_ids(100_000)
        publish_backfill_group_request(owner:, repository_ids:)
      end
    end
  end

  sig { returns(SecurityProductsEnablement::JobProgressTracker) }
  memoize def job_progress_tracker
    business_id = T.let(nil, T.nilable(Integer))
    if repository&.owner.present?
      business_id = repository&.owner&.business&.id
    end

    SecurityProductsEnablement::JobProgressTracker.new(T.must(repository&.owner_id), business_id)
  end

  sig { params(owner: User, repository_ids: T::Array[Integer]).void }
  def publish_backfill_group_request(owner:, repository_ids:)
    GitHub.logger.info("Publishing TSS backfill message")
    GlobalInstrumenter.instrument("secret_scanning.backfill.group", {
      action: :START,
      owner:,
      requested_at: Time.current.utc,
      type: :FULL,
      feature_flags: SecretScanning::Instrumentation::OwnerServiceFlags.new(owner).group_backfill_service_flags,
      repository_ids:,
      security_configuration_id: T.must(security_configuration).id,
    })
  end

  sig { returns(T.nilable(BlockedSettings::RepoCounter)) }
  memoize def repo_counter
    return nil unless repository
    BlockedSettings.new(T.must(repository&.owner)).repo_counter
  end

  # Determine if we should ignore GHAS features when selecting which features to enable:
  # - If a repository is public we will not skip GHAS features.
  # - If a repository already has GHAS enabled we will not skip GHAS features.
  #
  # - If a repository is restricted by policy we will skip GHAS features.
  # - If a repository owner hasn't purchashed GHAS we will skip GHAS features.
  # - If the org already exceeded the license limit we will skip GHAS features.
  #
  # - If the org has not exceeded the license limit:
  #   - If a repository does not have GHAS enabled but *does not* require additional licenses we will not skip.
  #   - If a repository does not have GHAS enabled but *does* require additional licenses we WILL skip.
  #
  sig { returns([T::Boolean, Symbol]) }
  def validate_skipping_ghas_features?
    repo = T.must(repository)
    owner = T.must(repo.owner)

    return false, :not_skipped if repo.public? && !GitHub.enterprise?
    return false, :not_skipped if repo.advanced_security_enabled?

    return true, :advanced_security_restricted_by_policy if !repo.policy_allows_advanced_security_enablement?
    return true, :advanced_security_not_purchased if !owner.advanced_security_purchased?
    return true, :seat_allowance_exceeded if owner.advanced_security_license.allowance_exceeded?

    seat_increase = AdvancedSecurityLicense.seat_usage_increase_if_advanced_security_enabled_for_repo(repo)
    if seat_increase > 0
      [true, :repo_consumes_additional_license]
    else
      [false, :not_skipped]
    end
  end

  sig { returns(T::Boolean) }
  memoize def applying_to_new_repo?
    arguments.dig(0, :reason) == :repo_creation || arguments.dig(0, :reason) == :repo_transfer
  end

  # Does nothing if all preconditions are met. If any precondition is not met,
  # raises either a RetryableError subclass or FatalError subclass depending
  # on whether we can reasonably expect a retry to succeed.
  sig { void }
  def check_preconditions!
    repository = self.repository
    if repository.nil?
      raise RepositoryDeleted, "Repository was deleted." if repository_deleted?

      raise RepositoryNotFound, "Repository not found."
    end

    if actor.nil?
      raise ActorNotFound, "Actor not found."
    end

    security_configuration = self.security_configuration
    if security_configuration.nil?
      raise SecurityConfigurationNotFound, "Security configuration not found."
    end

    if repository_security_configuration.nil?
      raise RepositorySecurityConfigurationNotFound, "Repository security configuration not found."
    end

    owner_id = security_configuration.target_type == "Business" ? repository.business&.id : repository.owner_id
    unless security_configuration.belongs_to_correct_target_id?(T.must(owner_id))
      raise SecurityConfigurationOwnerMismatch, "Security configuration target does not match repository's owner or enterprise"
    end
  rescue Error => error
    GitHub.logger.error(
      Body: error.message,
      "exception.type": error.class.name,
      "exception.message": error.message,
      "gh.code.function": __method__,
    )

    reason = T.must(error.class.name).demodulize.underscore
    retryable = error.is_a?(RetryableError)
    GitHub.dogstats.increment("apply_security_configuration_to_repository_job.skip", tags: ["reason:#{reason}", "retryable:#{retryable}"])

    raise
  end
end
