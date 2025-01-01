# typed: true
# frozen_string_literal: true

module SecurityProduct
  class TokenScanning < Service
    include GitHub::BatchMethod

    USER_ENABLED_KEY = "token_scanning.user_enabled"
    STAFF_DISABLED_KEY = "token_scanning.disabled"
    STAFF_NETWORK_DISABLED_KEY = "token_scanning.network_disabled"

    def initialize(repository)
      super(repository)
      @advanced_security_service = SecurityProduct::AdvancedSecurity.new(repository)
      @token_scanning = SecretScanning::Features::Repo::TokenScanning.new(repository)
      @public_scanning = SecretScanning::Features::Repo::PublicScanning.new(repository)
    end

    def enabled?
      @token_scanning.enabled?
    end

    def can_enable?(actor:, options:)
      if blocked_by_enterprise_policy?(actor, options)
        return Result.new(false, :token_scanning_restricted_by_enablement_policy)
      end

      # This service depends on AdvancedSecurity.
      # While this is already checked by the underlying feature, we want to surface this to programmatic users (ie. REST API).
      if SecretScanning::Features::AdvancedSecurityHelper.advanced_security_configurable?(repository) && !repository.advanced_security_enabled?
        return Result.new(false, :advanced_security_disabled)
      end

      if !@token_scanning.feature_available?
        return Result.new(false, :token_scanning_always_enabled_on_public_repo) if repository.public?
        return Result.new(false, :token_scanning_unavailable)
      end

      Result.new(true)
    end

    def on_enable(actor:, options:)
      renotify_only = options[:renotify_only] || false

      if renotify_only
        GlobalInstrumenter.instrument(
          "repository_secret_scanning.enable",
          {
            repository_id: repository.id
          }
        )

        return Result.new(ToggledServiceCollection.empty)
      end

      # short circuit early if secret scanning is already enabled on this repo.
      return Result.new(ToggledServiceCollection.empty) unless manually_disabled?

      use_staff_key = options[:use_staff_key] || false
      use_network_flag = options[:use_network_flag?] || false
      update_rest_of_network = options[:update_rest_of_network?] || false

      if use_staff_key
        if update_rest_of_network
          StafftoolsToggleNetworkTokenScanningJob.perform_later(repository.id, actor.id, true)
        end

        if use_network_flag
          @token_scanning.staff_network_unlock(actor: actor)
        else
          @token_scanning.staff_unlock(actor: actor)
        end
      else
        @token_scanning.enable(actor: actor)
      end

      if @token_scanning.ux_on_public_repo_enabled?
        GitHub.dogstats.increment("repository_secret_scanning.public_beta.enablement")

        GitHub.logger.info(
          "user has opted repository into secret scanning public beta for public repos",
          "code.function" => "on_enable",
          "code.namespace" => "SecurityProduct::TokenScanning",
          "gh.repo.id" => repository.id,
          "gh.actor.id" => actor.id,
        )
      end

      GitHub.instrument(
        "repository_secret_scanning.enable",
        secret_scanning_instrumentation_payload(actor, use_staff_key, use_network_flag))

      GlobalInstrumenter.instrument(
        "repository_secret_scanning.enable",
        {
          repository_id: repository.id
        }
      )

      instrument_enablement_change

      repository.ensure_backfill_scan_status

      # only skip backfill request if explicitly set to true
      if options[:skip_backfill_request] == true
        GitHub.logger.info(
          "Skipping backfill scan request for repo",
          "code.function" => "on_enable",
          "code.namespace" => "SecurityProduct::TokenScanning",
          "gh.actor.id" => actor.id,
          "gh.tss.enablement.options" => options,
          "gh.repo.id" => repository.id,
          "exception.stacktrace" => caller.take(10),
        )
      else
        repository.ensure_backfill_scan_if_enabled(actor: actor)
      end

      # Enable push protection if configured to
      should_enable_push_protection = false
      owner = repository.owner
      if owner&.user?
        should_enable_push_protection = SecretScanning::Features::User::PushProtection.new(owner).enabled_for_new_repos?

        if biz = ::AdvancedSecurity::Features::User::AdvancedSecurity.new(owner).get_business
          should_enable_push_protection ||= SecretScanning::Features::Business::PushProtection.new(biz).enabled_for_new_repos?
        end
      end
      if should_enable_push_protection
        result = enable_dependents(:token_scanning_push_protection, actor: actor, options: options)
        return Result.new(ToggledServiceCollection.create(to_sym, options).merge!(result.toggled_services), result.error)
      end

      Result.new(ToggledServiceCollection.create(to_sym, options))
    end

    def can_disable?(actor:, options:)
      if !@token_scanning.feature_available?
        Result.new(false, :token_scanning_unavailable)
      elsif blocked_by_enterprise_policy?(actor, options)
        Result.new(false, :token_scanning_restricted_by_enablement_policy)
      else
        Result.new(true)
      end
    end

    # Dependent services:
    #  - SecurityProduct::TokenScanningPushProtection
    #  - SecurityProduct::TokenScanningValidityChecks
    def on_disable(actor:, options:)
      # Don't disable secret scanning if this is an archive operation
      # We want to leave the state of Secret Scanning untouched, because repos should continue to be scanned even after being archived
      archive_operation = options[:on_archive?] || false
      return Result.new(ToggledServiceCollection.empty) if archive_operation

      dependent_results = disable_dependents(:token_scanning_push_protection, :token_scanning_validity_checks, :token_scanning_generic_secrets, :token_scanning_lower_confidence_patterns, :token_scanning_delegated_bypass, :token_scanning_delegated_closures, actor: actor, options: options)
      return dependent_results if dependent_results.error?

      use_staff_key = options[:use_staff_key] || false
      use_network_flag = options[:use_network_flag?] || false
      update_rest_of_network = options[:update_rest_of_network?] || false

      if use_staff_key
        if update_rest_of_network
          StafftoolsToggleNetworkTokenScanningJob.perform_later(repository.id, actor.id, false)
        end

        if use_network_flag
          @token_scanning.staff_network_disable(actor: actor)
        else
          @token_scanning.staff_disable(actor: actor)
        end
      else
        @token_scanning.disable(actor: actor)
      end

      if @token_scanning.ux_on_public_repo_enabled?
        GitHub.dogstats.decrement("repository_secret_scanning.public_beta.enablement")

        GitHub.logger.info(
          "user has opted repository out of secret scanning public beta for public repos",
          "code.function" => "on_disable",
          "code.namespace" => "SecurityProduct::TokenScanning",
          "gh.repo.id" => repository.id,
          "gh.actor.id" => actor.id,
        )
      end

      GitHub.instrument(
        "repository_secret_scanning.disable",
        secret_scanning_instrumentation_payload(actor, use_staff_key, use_network_flag))

      GlobalInstrumenter.instrument(
        "repository_secret_scanning.disable",
        {
          repository_id: repository.id
        }
      )

      instrument_enablement_change

      Result.new(ToggledServiceCollection.create(to_sym, options).merge!(dependent_results.toggled_services))
    end

    def to_sym
      :token_scanning
    end

    def self.name
      "Secret scanning"
    end

    def self.enabled_for_instance?
      GitHub.configuration_secret_scanning_enabled?
    end

    # Indicates whether token scanning was manually disabled by:
    #   staff through StaffTools
    #   or an user through repo settings.
    def manually_disabled?
      !repository.config.enabled?(USER_ENABLED_KEY) || staff_disabled?
    end

    # The batch method caches the return value of this method to avoid N+1 query
    batch_method(:"staff_disabled?") do |security_products|
      repos = security_products.map(&:repository)
      Configurable.preload_configuration(repos)
      security_products.index_with do |product|
        feature = SecretScanning::Features::Repo::TokenScanning.new(product.repository)
        feature.staff_disabled? || feature.staff_network_disabled?
      end
    end

    #For almost all use cases, use staff_disabled instead. This is only public for the
    #token_scanning_dependency to expose it to _token_scanning.html.erb
    def staff_network_disabled?
      @token_scanning.staff_network_disabled?
    end

    def self.error_to_message(symbol)
      case symbol
      when :advanced_security_disabled
        "Secret scanning can only be enabled on repos where Advanced Security is enabled."
      when :token_scanning_unavailable
        "Secret scanning is not available for this repository."
      when :token_scanning_always_enabled_on_public_repo
        "Secret scanning is always enabled for public repos."
      when :token_scanning_restricted_by_enablement_policy
        "Modifying secret scanning and push protection has been blocked by an enterprise policy. Contact your enterprise owner for details."
      else
        super
      end
    end

    private

    def instrument_enablement_change
      SecretScanning::Instrumentation::EnablementChangePublisher.publish_enablement_change_event_for_repository(repo: repository)
    end

    def secret_scanning_instrumentation_payload(actor, use_staff_key, network)
      payload = {
        user: actor,
        repo: repository,
        use_staff_key: use_staff_key,
        network?: network
      }

      if repository.in_organization?
        payload[:org] = repository.organization
      end

      payload
    end

    # Checks if toggling secret scanning is restricted by Configurable::SecretScanningSettingsPolicy
    def blocked_by_enterprise_policy?(actor, options)
      return false if options.present? && (options[:is_repo_creation] || options[:is_repo_transfer])
      SecurityProduct::Permissions::RepoAuthz.new(repository, actor:).manage_repo_secret_scanning_settings_blocked_by_policy?
    end
  end
end
