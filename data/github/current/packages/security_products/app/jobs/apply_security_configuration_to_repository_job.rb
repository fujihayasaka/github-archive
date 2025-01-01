# typed: true
# frozen_string_literal: true

class ApplySecurityConfigurationToRepositoryJob < ApplicationJob
  include GitHub::Memoizer
  include SecretScanning::Features::FeatureFlagHelper

  queue_as :security_configurations

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  Error = Class.new(StandardError)
  RetryableError = Class.new(Error)
  FatalError = Class.new(Error)
  RepositoryNotFound = Class.new(RetryableError)
  OwnerNotFound = Class.new(RetryableError)
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

    self.class.update_types(security_configuration).each { |update_type| repo_counter&.increment(update_type) }
  end

  after_perform :mark_job_as_completed

  def handle_permanent_job_failure(error)
    mark_job_as_completed
    mark_repository_security_configuration_as_failed(error)
  end

  def mark_job_as_completed
    # If the reason this job was enqueued was repo creation, we can skip progress updates:
    return if applying_to_new_repo?

    self.class.update_types(security_configuration).each { |update_type| repo_counter&.decrement(update_type) }

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
    "Code Security has not been purchased.",
    "Secret scanning is not available for this repository.",
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
      prevent_additional_sku_usage: T.nilable(T::Array[GitHub::Turboghas::SKU])
    ).void
  end
  def perform(actor_id:, repository_id:, security_configuration_id:, override_params: {}, reason: nil, prevent_additional_sku_usage: nil)
    GitHub.logger.info("Beginning job")

    check_preconditions!

    # if any of these are nil, the skip_reason guard above will prevent us from reaching this
    # so we can safely unwrap these optionals
    repository = T.must_because(self.repository) { "checked above" }
    actor = T.must_because(self.actor) { "checked above" }
    security_configuration = T.must_because(self.security_configuration) { "checked above" }
    repository_security_configuration = T.must_because(self.repository_security_configuration) { "checked above" }
    license_manager = SecurityProductsEnablement::LicenseValidator.new(repository, repository_owner, prevent_additional_sku_usage)

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
      license_manager,
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
      elsif security_configuration.enforced?(repository_owner)
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

    if license_manager.sku_needed?
      if repository_bundled?
        if security_configuration.enable_ghas && !license_manager.can_enable_sku?(sku: GitHub::Turboghas::SKU::Bundled)
          state = :failed
          error = license_manager.reason_restricted_from_enabling(sku: GitHub::Turboghas::SKU::Bundled).to_s
        end
      else
        is_ghr = security_configuration.is_github_recommended_configuration?
        if (is_ghr || security_configuration.code_security_sku_enabled?) && !license_manager.can_enable_sku?(sku: GitHub::Turboghas::SKU::CodeSecurity)
          state = :failed
          error = license_manager.reason_restricted_from_enabling(sku: GitHub::Turboghas::SKU::CodeSecurity).to_s
        elsif (is_ghr || security_configuration.secret_protection_sku_enabled?) && !license_manager.can_enable_sku?(sku: GitHub::Turboghas::SKU::SecretSecurity)
          state = :failed
          error = license_manager.reason_restricted_from_enabling(sku: GitHub::Turboghas::SKU::SecretSecurity).to_s
        end
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
      license_manager: SecurityProductsEnablement::LicenseValidator,
    ).returns(T::Hash[Symbol, T.any(String, T::Boolean)])
  end
  def toggle_services_params(repository, security_configuration, override_params, license_manager)
    # The installation_manager is used to determine if the feature is available in the instance.
    # This makes it possible to skip features that are (e.g.) not available on GHES.
    # The `_enabled?` is referred to the meta-configuration not the specific value for a repository.
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
      token_scanning_lower_confidence_patterns_enabled: !installation_manager.secret_scanning_enabled? ? "not_set" : security_configuration.secret_scanning_non_provider_patterns,
      token_scanning_validity_checks_enabled: !installation_manager.secret_scanning_enabled? ? "not_set" : security_configuration.secret_scanning_validity_checks,
      token_scanning_delegated_closures_enabled: !installation_manager.secret_scanning_enabled? ? "not_set" : security_configuration.secret_scanning_delegated_alert_dismissal,
      code_scanning_delegated_alert_dismissal_enabled: !installation_manager.code_scanning_delegated_alert_dismissal_enabled? ? "not_set" : security_configuration.code_scanning_delegated_alert_dismissal
    }

    # Generic Secrets is not available on GHES
    if !GitHub.enterprise? && repository_owner.feature_enabled?(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GENERIC_SECRETS_IN_SECURITY_CONFIGURATIONS)
      feature_params[:token_scanning_generic_secrets_enabled] = !installation_manager.secret_scanning_enabled? ? "not_set" : security_configuration.secret_scanning_generic_secrets
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

      service_manager_key = key.to_s.gsub(/_enabled$/, "").to_sym

      # If we're skipping GHAS features for this configuration only include free features in params:

      if repository_bundled?
        if license_manager.skip_enabling_sku_features?(sku: GitHub::Turboghas::SKU::Bundled)
          next unless service_manager_key.in?(SecurityProduct::ServiceManager::NON_GHAS_SERVICES.keys)
        end
      else
        if license_manager.skip_enabling_sku_features?(sku: GitHub::Turboghas::SKU::CodeSecurity)
          next if service_manager_key.in?(SecurityProduct::ServiceManager::CODE_SECURITY_FEATURES.keys)
        end

        if license_manager.skip_enabling_sku_features?(sku: GitHub::Turboghas::SKU::SecretSecurity)
          next if service_manager_key.in?(SecurityProduct::ServiceManager::SECRET_PROTECTION_SERVICES.keys)
        end
      end

      params[key] = (value == "enabled") ? "1" : "0"
    end

    if license_manager.sku_needed?
      if security_configuration.is_github_recommended_configuration? && repository_owner.organization? && !repository_bundled?
        params[:code_security_enabled] = license_manager.can_enable_sku?(sku: GitHub::Turboghas::SKU::CodeSecurity) ? "1" : "0"
      elsif security_configuration.is_a?(UnbundledSecurityConfiguration)
        # As the Secret Protection SKU is managed by the TokenScanning service we don't need to explicitly enable the SKU
        params[:code_security_enabled] = license_manager.can_enable_sku?(sku: GitHub::Turboghas::SKU::CodeSecurity) && security_configuration.code_security_sku_enabled? ? "1" : "0"
      else
        params[:advanced_security_enabled] = license_manager.can_enable_sku?(sku: GitHub::Turboghas::SKU::Bundled) && security_configuration.enable_ghas ? "1" : "0"
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
    if params[:vulnerability_updates_enabled] == "1" && repository_owner.vulnerability_updates_grouping_enabled_for_new_repos?
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
      params.delete(:token_scanning_delegated_closures_enabled)
    end

    # If we are dealing with a user repository, and are trying to apply a security configuration
    # we need to set the GHAS features to not_set so that they are not enabled or disabled by removing them from the params
    if !repository_owner.organization?
      params.delete(:advanced_security_enabled)
      params.delete(:auto_codeql_enabled)
      params.delete(:code_scanning_delegated_alert_dismissal_enabled)
      params.delete(:token_scanning_enabled)
      params.delete(:token_scanning_push_protection_enabled)
      params.delete(:token_scanning_delegated_bypass_enabled)
      params.delete(:token_scanning_delegated_closures_enabled)
    end

    params.merge!(repository.default_settings_for_features_not_in_security_configuration) if applying_to_new_repo?
    params.merge(override_params)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def logging_context
    # note we can't use repository_owner in this method as it will raise if the repository has been soft deleted
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
      "gh.security_configuration.apply_repo_job.prevent_additional_sku_usage": arguments.dig(0, :prevent_additional_sku_usage),
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

  sig { returns(T::Boolean) }
  memoize def repository_bundled?
    repo = repository
    repo.nil? ? true : repo.advanced_security_products_bundled?
  end

  sig { returns(User) }
  memoize def repository_owner
    repository&.owner or raise OwnerNotFound, "Repository Owner not found."
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
    return unless repository_owner.organization?

    finished = job_progress_tracker.decrement_jobs
    return unless finished

    if arguments.dig(0, :override_params, :skip_backfill_request).present?
      # The pop_repository_ids method returns nil when there are no more
      # repository IDs to pop off of the Redis set.
      while repository_ids = job_progress_tracker.pop_repository_ids(100_000)
        publish_backfill_group_request(owner: repository_owner, repository_ids:)
      end
    end
  rescue OwnerNotFound
    # if a repository is soft deleted this can be triggered
    # we don't actually care so lets swallow the exception and return
  end

  sig { returns(SecurityProductsEnablement::JobProgressTracker) }
  memoize def job_progress_tracker
    business_id = repository_owner.business&.id

    SecurityProductsEnablement::JobProgressTracker.new(repository_owner.id, business_id)
  end

  sig { params(owner: User, repository_ids: T::Array[Integer]).void }
  def publish_backfill_group_request(owner:, repository_ids:)
    GitHub.logger.info("Publishing TSS backfill message")
    GlobalInstrumenter.instrument("secret_scanning.backfill.group", {
      action: :START,
      owner:,
      requested_at: Time.current.utc,
      type: :FULL,
      feature_flags: SecretScanning::Instrumentation::OwnerServiceFlags.new(owner).group_backfill_service_flags(security_configuration),
      repository_ids:,
      security_configuration_id: T.must(security_configuration).id,
    })
  end

  sig { returns(T.nilable(BlockedSettings::RepoCounter)) }
  memoize def repo_counter
    return nil unless repository
    BlockedSettings.new(repository_owner).repo_counter
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

    repository_owner # this will raise if it doesn't exist

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

    owner_id = security_configuration.target_type == "Business" ? repository.business&.id : repository_owner.id
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

  # Returns an array of symbols, each one mapping to a GHAS feature.
  # The symbols represent the update_type that will be incremented/decremented in the repo_counter of BlockedSettings
  sig { params(security_configuration: T.nilable(SecurityConfiguration)).returns(T::Array[Symbol]) }
  def self.update_types(security_configuration)
    return [] unless security_configuration

    update_types = [T.must(security_configuration).enable_ghas ? :advanced_security_enable_all : :advanced_security_disable_all]
    update_types + [
      [:code_scanning, :auto_codeql_enable_all, :auto_codeql_disable_all],
      [:secret_scanning, :secret_scanning_enable_all, :secret_scanning_disable_all],
      [:secret_scanning_validity_checks, :secret_scanning_validity_checks_enable_all, :secret_scanning_validity_checks_disable_all],
      [:secret_scanning_push_protection, :secret_scanning_push_protection_enable_all, :secret_scanning_push_protection_disable_all]
    ].map do |feature, enable_type, disable_type|
      security_configuration.send("#{feature}_enabled?") ? enable_type : disable_type
    end
  end
end
