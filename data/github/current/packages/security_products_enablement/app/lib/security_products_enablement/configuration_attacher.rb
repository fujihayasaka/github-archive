# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  # Synchronously applies a SecurityConfiguration's feature settings to a single
  # Repository. This is the core attachment logic extracted from
  # ApplySecurityConfigurationToRepositoryJob so that multiple entry points
  # (the legacy job and, in Milestone 2, the Hydro attacher) can share it.
  #
  # Callers pass IDs and this class is responsible for loading the records,
  # validating preconditions (raising typed errors that callers can pattern-
  # match for retry/discard semantics), and performing the attachment.
  #
  # This class does NOT interact with the JobProgressTracker — that remains
  # the responsibility of the calling job.
  #
  # See:
  # - https://github.com/github/security-products-enablement/issues/2797
  # - https://github.com/github/security-products-enablement/blob/main/docs/adrs/2026-03-18-security-configuration-attachment-pipeline.md
  class ConfigurationAttacher
    include GitHub::Memoizer
    include SecretScanning::Features::FeatureFlagHelper

    # The successful outcome of an attachment attempt. The symbol mirrors the
    # value written to the corresponding RepositorySecurityConfiguration row
    # (either :attached or :enforced). Failures are returned as
    # GH::Result::Error whose message is the underlying failure reason.
    Result = T.type_alias { GH::Result[Symbol] }

    # Precondition errors. Callers (e.g. ActiveJob's retry_on/discard_on) can
    # match on RetryableError vs FatalError to decide whether to retry.
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
    OwnerDeleted = Class.new(FatalError)

    sig { returns(Integer) }
    attr_reader :actor_id

    sig { returns(Integer) }
    attr_reader :repository_id

    sig { returns(Integer) }
    attr_reader :security_configuration_id

    sig { returns(T::Hash[Symbol, String]) }
    attr_reader :service_manager_overrides

    sig { returns(T.nilable(Symbol)) }
    attr_reader :reason

    sig { returns(T.nilable(T::Array[GitHub::Turboghas::SKU])) }
    attr_reader :disallowed_skus

    # Namespace used for dogstats metrics and structured log keys. Callers may
    # override this so that downstream consumers (the legacy job, the Hydro
    # attacher in Milestone 2, etc.) emit caller-attributable telemetry.
    sig { returns(String) }
    attr_reader :instrumentation_namespace

    sig do
      params(
        actor_id: Integer,
        repository_id: Integer,
        security_configuration_id: Integer,
        service_manager_overrides: T::Hash[Symbol, String],
        reason: T.nilable(Symbol),
        disallowed_skus: T.nilable(T::Array[GitHub::Turboghas::SKU]),
        instrumentation_namespace: String,
      ).void
    end
    def initialize(actor_id:, repository_id:, security_configuration_id:, service_manager_overrides: {}, reason: nil, disallowed_skus: nil, instrumentation_namespace: "security_products_enablement.configuration_attacher")
      @actor_id = actor_id
      @repository_id = repository_id
      @security_configuration_id = security_configuration_id
      @service_manager_overrides = T.let(service_manager_overrides.dup, T::Hash[Symbol, String])
      @reason = reason
      @disallowed_skus = disallowed_skus
      @instrumentation_namespace = instrumentation_namespace
    end

    # Loaders. These are best-effort — callers should call check_preconditions!
    # (or attach!, which calls it) before relying on the records being present.

    sig { returns(T.nilable(::Repository)) }
    memoize def repository
      Repositories::Public.find_active(repository_id)
    end

    sig { returns(T.nilable(User)) }
    memoize def actor
      User.find_by(id: actor_id)
    end

    sig { returns(T.nilable(SecurityConfiguration)) }
    memoize def security_configuration
      SecurityConfiguration.find_by(id: security_configuration_id)
    end

    sig { returns(T.nilable(RepositorySecurityConfiguration)) }
    memoize def repository_security_configuration
      repo = repository
      config = security_configuration
      return unless repo && config
      RepositorySecurityConfiguration.find_by(repository_id: repo.id, security_configuration_id: config.id)
    end

    sig { returns(T::Boolean) }
    def repository_deleted?
      Repositories::Public.is_deleted?(repository_id)
    end

    # Validates that all referenced records are loadable and consistent.
    # Raises a RetryableError or FatalError subclass on failure and emits a
    # "#{instrumentation_namespace}.skip" dogstats counter tagged with the
    # error class and whether it's retryable.
    sig { void }
    def check_preconditions!
      repo = repository
      if repo.nil?
        raise RepositoryDeleted, "Repository was deleted." if repository_deleted?
        raise RepositoryNotFound, "Repository not found."
      end

      repo_owner = repo.owner
      raise OwnerNotFound, "Repository Owner not found." if repo_owner.nil?
      if repo_owner.is_a?(Organization) && repo_owner.soft_deleted?
        raise OwnerDeleted, "Repository owner was deleted."
      end

      raise ActorNotFound, "Actor not found." if actor.nil?

      config = security_configuration
      raise SecurityConfigurationNotFound, "Security configuration not found." if config.nil?

      raise RepositorySecurityConfigurationNotFound, "Repository security configuration not found." if repository_security_configuration.nil?

      owner_id = config.target_type == "Business" ? repo.business&.id : repo_owner.id
      unless config.belongs_to_correct_target_id?(owner_id)
        raise SecurityConfigurationOwnerMismatch, "Security configuration target does not match repository's owner or enterprise"
      end
    rescue Error => error
      GitHub.logger.error(
        Body: error.message,
        "exception.type": error.class.name,
        "exception.message": error.message,
        "gh.code.function": __method__,
      )

      reason_tag = T.must(error.class.name).demodulize.underscore
      retryable = error.is_a?(RetryableError)
      GitHub.dogstats.increment("#{instrumentation_namespace}.skip", tags: ["reason:#{reason_tag}", "retryable:#{retryable}"])

      raise
    end

    # Validates preconditions, applies the configuration's feature settings to
    # the repository, and writes the resulting state to the
    # RepositorySecurityConfiguration.
    #
    # On success returns GH::Result::Ok wrapping the resulting state symbol
    # (:attached or :enforced). Expected attachment failures (e.g. license
    # restrictions, ServiceManager errors) are returned as GH::Result::Error;
    # precondition failures and unexpected errors (DB errors from update!,
    # ServiceManager exceptions) are raised so callers can apply their own
    # retry semantics.
    sig { returns(Result) }
    def attach!
      check_preconditions!

      license_manager = SecurityProductsEnablement::LicenseValidator.new(repository!, repository_owner, disallowed_skus)

      # Build the per-call overrides hash without mutating the ivar so the
      # instance stays reusable and the original caller-supplied hash is
      # untouched.
      #
      # Because we are making changes to repository security settings based on a configuration update, we need to let
      # the toggle services method know. This will allow us to skip some checks pertaining to configuration enforcement.
      # Values are stringly-typed ("1") to match the rest of the form-style params and the
      # controller flow at app/controllers/repos/security_and_analysis/settings_controller.rb;
      # SecurityProduct::ServiceManager treats them as truthy regardless.
      overrides = service_manager_overrides.merge(enablement_action: "security_configuration_enablement")
      overrides = overrides.merge(is_repo_creation: "1") if applying_to_new_repo?
      overrides = overrides.merge(is_repo_unarchived: "1") if applying_to_unarchived_repo?

      params = toggle_services_params(license_manager, overrides)

      GitHub.logger.info("Calling SecurityProduct::ServiceManager with params: #{params.inspect}")

      result = SecurityProduct::ServiceManager
        .new(repository!)
        .toggle_services_with_form_inputs(
          actor!,
          params:,
          use_human_readable_error: true,
          skip_instrumentation: applying_to_new_repo?
        )

      error = T.let(result.error&.to_s, T.nilable(String))
      state =
        if error
          :failed
        elsif security_configuration!.enforced?(repository_owner)
          :enforced
        else
          :attached
        end

      GitHub.logger.info("SecurityProduct::ServiceManager result: #{result.to_a.inspect}")
      GitHub.dogstats.increment("#{instrumentation_namespace}.result", tags: ["state:#{state}"])

      if repository!.archived?
        GitHub.dogstats.increment("#{instrumentation_namespace}.on_archived_repository", tags: ["state:#{state}"])
      end

      if error
        is_handled = SecurityProductsEnablement.domain.failures.known?(error)
        GitHub.logger.error(
          "#{instrumentation_namespace}.service_manager_error": error,
          "#{instrumentation_namespace}.service_manager_error_handled": is_handled
        )
        GitHub.dogstats.increment("#{instrumentation_namespace}.error", tags: ["handled:#{is_handled}", "error:#{error}"])
      end

      # License validation only applies to non-archived repositories
      if !repository!.archived? && license_manager.sku_needed?
        if repository_bundled? && !security_configuration!.is_a?(UnbundledSecurityConfiguration)
          if security_configuration!.enable_ghas && !license_manager.can_enable_sku?(sku: GitHub::Turboghas::SKU::Bundled)
            state = :failed
            error = license_manager.reason_restricted_from_enabling(sku: GitHub::Turboghas::SKU::Bundled).to_s
          end
        else
          is_ghr = security_configuration!.is_github_recommended_configuration?
          if (is_ghr || security_configuration!.code_security_sku_enabled?) && !license_manager.can_enable_sku?(sku: GitHub::Turboghas::SKU::CodeSecurity)
            state = :failed
            error = license_manager.reason_restricted_from_enabling(sku: GitHub::Turboghas::SKU::CodeSecurity).to_s
          elsif (is_ghr || security_configuration!.secret_protection_sku_enabled?) && !license_manager.can_enable_sku?(sku: GitHub::Turboghas::SKU::SecretSecurity)
            state = :failed
            error = license_manager.reason_restricted_from_enabling(sku: GitHub::Turboghas::SKU::SecretSecurity).to_s
          elsif security_configuration!.enable_ghas && !license_manager.can_enable_sku?(sku: GitHub::Turboghas::SKU::Bundled)
            state = :failed
            error = license_manager.reason_restricted_from_enabling(sku: GitHub::Turboghas::SKU::Bundled).to_s
          end
        end
      end

      RepositorySecurityConfiguration.throttle_with_retry do
        repository_security_configuration!.update!(state: state, failure_reason: error)
      end

      enqueue_security_overview_analytics_remediation

      if error
        GH::Result::Error[Symbol].new(error)
      else
        GH::Result::Ok[Symbol].new(state)
      end
    end

    private

    # Bang accessors for the loaded records. Safe to call after
    # check_preconditions! has succeeded; will raise NoMethodError on nil
    # otherwise (which is a programmer bug, not an expected failure mode).

    sig { returns(::Repository) }
    def repository!
      T.must(repository)
    end

    sig { returns(User) }
    def actor!
      T.must(actor)
    end

    sig { returns(SecurityConfiguration) }
    def security_configuration!
      T.must(security_configuration)
    end

    sig { returns(RepositorySecurityConfiguration) }
    def repository_security_configuration!
      T.must(repository_security_configuration)
    end

    sig { returns(User) }
    memoize def repository_owner
      T.cast(repository!.owner, User)
    end

    sig { returns(T::Boolean) }
    memoize def repository_bundled?
      repository!.advanced_security_products_bundled?
    end

    sig { returns(T::Boolean) }
    def applying_to_new_repo?
      reason == :repo_creation || reason == :repo_transfer
    end

    sig { returns(T::Boolean) }
    def applying_to_unarchived_repo?
      reason == :repo_unarchived
    end

    # Builds the parameter hash for SecurityProduct::ServiceManager#toggle_services_with_form_inputs,
    # mirroring what the security & analysis settings form would produce.
    sig do
      params(
        license_manager: SecurityProductsEnablement::LicenseValidator,
        overrides: T::Hash[Symbol, String],
      ).returns(T::Hash[Symbol, T.any(String, T::Boolean)])
    end
    def toggle_services_params(license_manager, overrides)
      # The installation_manager is used to determine if the feature is available in the instance.
      # This makes it possible to skip features that are (e.g.) not available on GHES.
      # The `_enabled?` is referred to the meta-configuration not the specific value for a repository.
      installation_manager = SecurityProductsEnablement::SecurityProductsManager.new

      feature_params = {
        private_vulnerability_reporting_enabled: !installation_manager.private_vulnerability_reporting_enabled? ? "not_set" : security_configuration!.private_vulnerability_reporting,
        dependency_graph_enabled: !installation_manager.dependency_graph_enabled? ? "not_set" : security_configuration!.dependency_graph,
        dependency_graph_autosubmit_action_enabled: !installation_manager.dependency_graph_autosubmit_action_enabled? ? "not_set" : security_configuration!.dependency_graph_autosubmit_action,
        vulnerability_alerts_enabled: !installation_manager.dependabot_alerts_enabled? ? "not_set" : security_configuration!.dependabot_alerts,
        vulnerability_updates_enabled: !installation_manager.dependabot_security_updates_enabled? ? "not_set" : security_configuration!.dependabot_security_updates,
        vulnerability_alerts_delegated_closures_enabled: !installation_manager.dependabot_delegated_alert_dismissal_enabled? ? "not_set" : security_configuration!.dependabot_delegated_alert_dismissal,
        dependabot_malware_alerts_enabled: !installation_manager.dependabot_malware_alerts_enabled? ? "not_set" : security_configuration!.dependabot_malware_alerts,
        auto_codeql_enabled: (!installation_manager.code_scanning_default_setup_enabled? || !should_try_and_adjust_auto_codeql_for_repo?) ? "not_set" : security_configuration!.code_scanning,
        token_scanning_enabled: !installation_manager.secret_scanning_enabled? ? "not_set" : security_configuration!.secret_scanning,
        token_scanning_push_protection_enabled: !installation_manager.secret_scanning_enabled? ? "not_set" : security_configuration!.secret_scanning_push_protection,
        token_scanning_delegated_bypass_enabled: !installation_manager.secret_scanning_enabled? ? "not_set" : security_configuration!.secret_scanning_delegated_bypass,
        token_scanning_lower_confidence_patterns_enabled: !installation_manager.secret_scanning_enabled? ? "not_set" : security_configuration!.secret_scanning_non_provider_patterns,
        token_scanning_validity_checks_enabled: !installation_manager.secret_scanning_enabled? ? "not_set" : security_configuration!.secret_scanning_validity_checks,
        token_scanning_delegated_closures_enabled: !installation_manager.secret_scanning_enabled? ? "not_set" : security_configuration!.secret_scanning_delegated_alert_dismissal,
        code_scanning_delegated_alert_dismissal_enabled: !installation_manager.code_scanning_delegated_alert_dismissal_enabled? ? "not_set" : security_configuration!.code_scanning_delegated_alert_dismissal
      }

      # Generic Secrets is not available on GHES
      if !GitHub.enterprise? && repository_owner.feature_flag_enabled_or_raise?(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GENERIC_SECRETS_IN_SECURITY_CONFIGURATIONS) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        feature_params[:token_scanning_generic_secrets_enabled] = !installation_manager.secret_scanning_enabled? ? "not_set" : security_configuration!.secret_scanning_generic_secrets
      end

      if GitHub.secret_scanning_extended_metadata_available_on_instance?
        feature_params[:token_scanning_partner_metadata_enabled] = !installation_manager.secret_scanning_enabled? ? "not_set" : security_configuration!.secret_scanning_extended_metadata
      end

      params = { skip_if_enabled: true, skip_if_disabled: true, ignore_import: true }

      feature_params.each do |key, value|
        next if value == "not_set"
        next if key == :private_vulnerability_reporting_enabled && repository!.private? # PVR is only available to public repos

        service_manager_key = key.to_s.gsub(/_enabled\z/, "").to_sym

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
        if security_configuration!.is_github_recommended_configuration? && repository_owner.organization? && !repository_bundled?
          params[:code_security_enabled] = license_manager.can_enable_sku?(sku: GitHub::Turboghas::SKU::CodeSecurity) ? "1" : "0"
        elsif security_configuration!.is_a?(UnbundledSecurityConfiguration)
          # As the Secret Protection SKU is managed by the TokenScanning service we don't need to explicitly enable the SKU
          # With ternary state support: handle true/false/nil explicitly
          if security_configuration!.code_security_sku_enabled == true && license_manager.can_enable_sku?(sku: GitHub::Turboghas::SKU::CodeSecurity)
            params[:code_security_enabled] = "1"
          elsif security_configuration!.code_security_sku_enabled == false
            params[:code_security_enabled] = "0"
          end
          # When nil (not_set), don't set the parameter to avoid overriding repo settings
        else
          params[:advanced_security_enabled] = license_manager.can_enable_sku?(sku: GitHub::Turboghas::SKU::Bundled) && security_configuration!.enable_ghas ? "1" : "0"
        end
      end

      if params[:auto_codeql_enabled] == "1"
        params[:fail_on_manual_workflow] = "1"
        code_scanning_opts = CodeScanning::AutoCodeql::Options.new_from_hash(security_configuration!.code_scanning_options)
        unless code_scanning_opts.not_set?
          params[:auto_codeql_runner_type] = code_scanning_opts.runner_type
          params[:auto_codeql_runner_label] = code_scanning_opts.runner_label
        end
      end

      # If autosubmit is enabled, map persisted options unto the respective SecurityProduct::SettingsForm param
      if params[:dependency_graph_autosubmit_action_enabled] == "1"
        dgas_options = SecurityProduct::DependencyGraphAutosubmitAction::Options.new_from_hash(
          security_configuration!.dependency_graph_autosubmit_action_options
        )

        params[:dependency_graph_autosubmit_action_use_labeled_runners] = dgas_options.labeled_runners ? "1" : "0"
      end

      # If it is the GH recommended config and Dependabot alerts are enabled, enable the default Dependabot rule
      if params[:vulnerability_alerts_enabled] == "1" && security_configuration!.is_github_recommended_configuration?
        params[:dependabot_alerts_global_rule_enabled] = "1"
      end

      # If security updates are being enabled, we also enable grouped security updates if it's selected in the global settings page
      if params[:vulnerability_updates_enabled] == "1" && repository_owner.vulnerability_updates_grouping_enabled_for_new_repos?
        params[:vulnerability_updates_grouping_enabled] = "1"
      end

      if repository!.archived?
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

      # If paid secret protection features are not available, remove them from the params
      # This is the case for:
      # - Public repos on free orgs
      if !SecretScanning::Features::AdvancedSecurityHelper.secret_scanning_available?(repository!)
        params.delete(:token_scanning_lower_confidence_patterns_enabled)
        params.delete(:token_scanning_validity_checks_enabled)
        params.delete(:token_scanning_delegated_closures_enabled)
        params.delete(:token_scanning_generic_secrets_enabled)
        params.delete(:token_scanning_partner_metadata_enabled)
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

      params.merge!(repository!.default_settings_for_features_not_in_security_configuration(actor: actor!)) if applying_to_new_repo?
      params.merge!(overrides)
    end

    # If the security configuration specifies that advanced code scanning setup is allowed
    # then we shouldn't try and enable default setup if the repository is using / trying to
    # use CodeQL via advanced setup.
    #
    # If the repo is just uploading results from a non-CodeQL tool via the API, we can
    # still turn on CodeQL default setup, because that can coexist with other tools.
    #
    # If they're trying to disable Default Setup rather than enable it, then we should
    # allow that regardless of whether advanced setup is in use or not.
    sig { returns(T::Boolean) }
    def should_try_and_adjust_auto_codeql_for_repo?
      # When code_scanning is disabled, the service's options are reset and so allow_advanced
      # wouldn't be set anyway (see `SecurityConfiguration#clear_code_scanning_options_if_disabled`).
      # But it's better to be explicit about intent here rather than relying on that side effect.
      return true if security_configuration!.code_scanning == "disabled"

      return true unless security_configuration!.code_scanning_general_options&.dig("allow_advanced") == true

      !CodeScanning::AutoCodeql.new(repository!).has_advanced_codeql_setup?
    end

    # Enqueues a near-real-time remediation of the SecurityOverviewAnalytics
    # FeatureStatusRevision record for this repository after a security
    # configuration apply attempt, including failure-state, so the Security
    # Overview Coverage page reflects the repository's latest post-attempt
    # state without waiting for the batch reconciliation pipeline.
    sig { void }
    def enqueue_security_overview_analytics_remediation
      begin
        SecurityOverviewAnalytics::Reconciliation::RepositoryFeatureStatusDeviationRemediationJob.perform_later(
          repository_id: repository!.id,
          session_id: "realtime:#{instrumentation_namespace}:#{SecureRandom.uuid}",
        )
      rescue StandardError => e
        # The remediation enqueue is best-effort; never fail the apply because
        # of analytics bookkeeping. Batch reconciliation will catch up if this errors.
        GitHub.logger.warn(
          "Failed to enqueue SecurityOverviewAnalytics remediation after security configuration apply",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.repo.id": repository!.id,
          "exception.type": e.class.name,
          "exception.message": e.message,
          "exception.stacktrace": e.backtrace&.first(20)&.join("\n"),
        )
        Failbot.report(e, app: "github-security-center")
      end
    end
  end
end
