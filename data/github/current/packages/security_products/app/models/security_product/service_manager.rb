# typed: strict
# frozen_string_literal: true

# This manager class is intended to serve as a namespace for encapsulating
# repository-oriented business logic that modifies or interacts with more than
# one service at a time. For example, when a user submits form data, it is this
# class that is concerned with converting the form into a set of services to
# toggle, and it is this class that is concerned with how services should be
# enabled in bulk.

# Use this namespace for any business logic that touches multiple services at
# the same time.
#
# Note that tests for this class are at test/integration/security_product/services_test.rb
module SecurityProduct
  class ServiceManager
    include InsightsHelper
    include Insights::InsightsIngestionHelper # used in dependent code
    include SecretScanning::Features::FeatureFlagHelper

    ServiceOptions = T.type_alias { T::Hash[Symbol, T.untyped] }
    ServiceList = T.type_alias { T.any(T::Array[Symbol], T::Array[[Symbol, ServiceOptions]]) }

    # The order in which these services are defined is important. See following
    # comment.
    SERVICES = T.let({
      private_vulnerability_reporting: SecurityProduct::PrivateVulnerabilityReporting,
      dependency_graph: SecurityProduct::DependencyGraph,
      dependency_graph_autosubmit_action: SecurityProduct::DependencyGraphAutosubmitAction,
      vulnerability_alerts: SecurityProduct::VulnerabilityAlerts,
      vulnerability_updates: SecurityProduct::VulnerabilityUpdates,
      vulnerability_updates_grouping: SecurityProduct::VulnerabilityUpdatesGrouping,
      advanced_security: SecurityProduct::AdvancedSecurity,
      token_scanning: SecurityProduct::TokenScanning,
      token_scanning_push_protection: SecurityProduct::TokenScanningPushProtection,
      token_scanning_validity_checks: SecurityProduct::TokenScanningValidityChecks,
      token_scanning_lower_confidence_patterns: SecurityProduct::TokenScanningLowerConfidencePatterns,
      token_scanning_generic_secrets: SecurityProduct::TokenScanningGenericSecrets,
      token_scanning_delegated_bypass: SecurityProduct::TokenScanningDelegatedBypass,
      token_scanning_delegated_closures: SecurityProduct::TokenScanningDelegatedClosures,
      code_security: SecurityProduct::CodeSecurity,
      auto_codeql: CodeScanning::AutoCodeql,
      code_scanning_delegated_alert_dismissal: CodeScanning::AlertDismissalService,
      code_quality: CodeQualityEnablement,
      dependabot_config_file: SecurityProduct::DependabotConfigFile,
      dependabot_on_actions: SecurityProduct::DependabotOnActions,
      dependabot_self_hosted: SecurityProduct::DependabotSelfHosted,
      dependabot_autofix: SecurityProduct::DependabotAutofix,
      innersource_advisories: SecurityProduct::InnersourceAdvisories,
    }, T::Hash[Symbol, T.class_of(SecurityProduct::Service)])
    SYMBOLS = T.let(SERVICES.invert, T::Hash[T.class_of(SecurityProduct::Service), Symbol])


    # Advanced Security services are gated by a SKU. The following services
    # are free, and not gated, hence "Non Advanced Security"
    NON_GHAS_SERVICES = T.let(SERVICES.slice(:dependency_graph,
                                       :vulnerability_alerts,
                                       :vulnerability_updates,
                                       :vulnerability_updates_grouping,
                                       :dependabot_config_file,
                                       :dependabot_on_actions,
                                       :dependabot_self_hosted,
                                       :dependabot_autofix,
                                       :private_vulnerability_reporting), T::Hash[Symbol, T.class_of(SecurityProduct::Service)])

    # These services require the Secret Protection SKU
    SECRET_PROTECTION_SERVICES = T.let(SERVICES.slice(:token_scanning,
      :token_scanning_push_protection,
      :token_scanning_validity_checks,
      :token_scanning_lower_confidence_patterns,
      :token_scanning_generic_secrets,
      :token_scanning_delegated_bypass,
      :token_scanning_delegated_closures), T::Hash[Symbol, T.class_of(SecurityProduct::Service)])

    # These services require the Code Security SKU
    CODE_SECURITY_FEATURES = T.let(SERVICES.slice(:code_security,
      :auto_codeql,
      :code_scanning_delegated_alert_dismissal,
      :dependency_graph_autosubmit_action,
      :innersource_advisories,
      :code_quality), T::Hash[Symbol, T.class_of(SecurityProduct::Service)])

    # Normally, we enable one service at a time. But in some scenarios,
    # for example when new repos are created, we may enable multiple
    # services at the same time.
    #
    # When we enable multiple services at the same time, the order in which
    # the services are enabled matters. For example, if we are enabling
    # TokenScanning *and* AdvancedSecurity, then AdvancedSecurity must be
    # enabled first – or else, TokenScanning will not actually turn on.
    #
    # For that reason, we encode the ordering defined above into a
    # {service_sym: integer_index} hash that we can use for sorting services
    # before we enable or disable them.

    SERVICES_SORT_ORDER = T.let(SERVICES.each_with_index.reduce({}) do |h, ((sym, _klass), i)|
      h[sym] = i; h
    end, T::Hash[Symbol, Integer])

    SERVICES_IN_SECURITY_CONFIGURATION = T.let(%i(
      private_vulnerability_reporting
      dependency_graph
      dependency_graph_autosubmit_action
      vulnerability_alerts
      vulnerability_updates
      advanced_security
      token_scanning
      token_scanning_push_protection
      token_scanning_validity_checks
      token_scanning_lower_confidence_patterns
      token_scanning_delegated_bypass
      token_scanning_delegated_closures
      token_scanning_generic_secrets
      code_security
      auto_codeql
      code_scanning_delegated_alert_dismissal
    ), T::Array[Symbol])

    sig { returns(T::Hash[Symbol, T.class_of(SecurityProduct::Service)]) }
    def self.all_services
      SERVICES
    end

    sig { params(sym: Symbol).returns(T.nilable(T.class_of(SecurityProduct::Service))) }
    def self.find_service(sym)
      SERVICES[sym]
    end

    sig { returns(Repository) }
    attr_reader :repository

    class Action < T::Enum
      enums do
        Enable = new
        Disable = new
      end
    end

    sig { params(repository: Repository).void }
    def initialize(repository)
      @repository = repository
    end

    sig do
      params(
        actor: User,
        services_to_disable: ServiceList,
        services_to_enable: ServiceList,
        skip_instrumentation: T::Boolean,
        use_human_readable_error: T::Boolean
      )
      .returns(Result)
    end
    def toggle_services(actor, services_to_disable: [], services_to_enable: [], skip_instrumentation: false, use_human_readable_error: false)
      GitHub.logger.with_named_tags(
        "code.namespace": self.class.name,
        "code.function": __method__,
        "enduser.id": actor.display_login,
        "gh.actor.id": actor.id,
        "gh.actor.login": actor.display_login,
        "gh.actor.type": actor.class.name,
        "gh.repo.id": repository.id,
        "gh.repo.name": repository.name,
        "gh.repo.visibility": repository.visibility,
        "gh.owner.id": repository.owner_id,
        "gh.owner.login": repository.owner_display_login,
      ) do
        from_services_hash = Api::Serializer.serialize(:security_and_analysis_hash, repository)
        error_result = T.let(nil, T.nilable(Result::Error))
        error = T.let(nil, T.nilable(Result::Error))

        # As mentioned above, order matters when enabling multiple services.
        # For disabling, we reverse that order. Order is more important for
        # enablement than disablement, but it makes sense to be cautious.
        mapped_services_to_disable = map_to_services(services_to_disable).reverse
        mapped_services_to_enable = map_to_services(services_to_enable)
        service_syms_to_disable = mapped_services_to_disable.map(&:last)
        service_syms_to_enable = mapped_services_to_enable.map(&:last)

        GitHub.logger.info(<<~LOG)
          Services to disable: #{service_syms_to_disable.inspect}
          Services to enable: #{service_syms_to_enable.inspect}
          Skip instrumentation: #{skip_instrumentation.inspect}
          Use human readable error: #{use_human_readable_error.inspect}
          LOG

        all_disabled_services = ToggledServiceCollection.empty
        all_enabled_services = ToggledServiceCollection.empty

        # Prepare a shared runner checker so we do not hit Actions Twirp endpoints if multiple services
        # need to check runner information for the repository.
        actions_runner_checker = SecurityProductsEnablement::Actions::RunnerChecker.new(repository)

        mapped_services_to_disable.each do |(service_klass, opt, service_sym)|
          GitHub.logger.info("Disabling service: #{service_sym.inspect}")

          service = service_klass.new(repository)
          # Attach the repository's runner checker if the service implements checks against it
          if service.is_a?(SecurityProduct::Service::ActionsChecks)
            service.actions_runner_checker = actions_runner_checker
          end

          disabled_result = disable_service(service, actor:, options: opt)
          error_result = disabled_result.error
          error = error_result && use_human_readable_error ? service_klass.error_to_message(error_result) : error_result

          all_disabled_services.merge!(disabled_result.toggled_services)

          if error_result
            GitHub.logger.warn(<<~LOG, "exception.type": error_result, "exception.message": error)
              Error while disabling service: #{service_sym.inspect}
              Error: #{error.inspect}
              Disabled services: #{all_disabled_services.services.inspect}
              LOG

            break
          else
            GitHub.logger.info(<<~LOG)
              Successfully disabled service: #{service_sym.inspect}
              Disabled services: #{all_disabled_services.services.inspect}
              LOG
          end
        end

        # Skip enablement if disablement failed.
        if error_result.nil?
          mapped_services_to_enable.each do |(service_klass, opt, service_sym)|
            GitHub.logger.info("Enabling service: #{service_sym.inspect}")

            service = service_klass.new(repository)
            # Attach the repository's runner checker if the service implements checks against it
            if service.is_a?(SecurityProduct::Service::ActionsChecks)
              service.actions_runner_checker = actions_runner_checker
            end

            enabled_result = enable_service(
              service,
              actor: actor,
              options: opt
            )
            enabled_services = enabled_result.toggled_services
            error_result = enabled_result.error
            error = error_result && use_human_readable_error ? service_klass.error_to_message(error_result) : error_result

            all_enabled_services.merge!(enabled_services)

            if error_result
              GitHub.logger.warn(<<~LOG, "exception.type": error_result, "exception.message": error)
                Error while enabling service: #{service_sym.inspect}
                Error: #{error.inspect}
                Disabled services: #{all_disabled_services.services.inspect}
                Enabled services: #{all_enabled_services.services.inspect}
                LOG

              break
            else
              GitHub.logger.info(<<~LOG)
                Successfully enabled service: #{service_sym.inspect}
                Disabled services: #{all_disabled_services.services.inspect}
                Enabled services: #{all_enabled_services.services.inspect}
                LOG
            end
          end
        end

        toggled_services = ToggledServiceCollection.empty
        toggled_services.merge!(all_disabled_services)
        toggled_services.merge!(all_enabled_services)

        GitHub.logger.info(<<~LOG)
          Finished toggling services: #{toggled_services.services.inspect}
          Disabled services: #{all_disabled_services.services.inspect}
          Enabled services: #{all_enabled_services.services.inspect}
          Error: #{error.inspect}
          LOG

        instrument_on_services_toggled(actor, toggled_services, from_services_hash) unless skip_instrumentation

        Result.new(toggled_services, error)
      end
    end

    # accepts parameters from the security & analysis form
    # and enables or disables services accordingly.
    # STOP: Unless you have already have params from a form, you should use toggle_services instead
    sig do
      params(
        actor: User,
        params: T.untyped,
        use_human_readable_error: T::Boolean,
        skip_instrumentation: T::Boolean
      )
      .returns(SecurityProduct::Result)
    end
    def toggle_services_with_form_inputs(actor, params:, use_human_readable_error: false, skip_instrumentation: false)
      form = SecurityProduct::SettingsForm.new(params, repository:)
      toggle_services(
        actor,
        services_to_disable: form.services_to_disable,
        services_to_enable: form.services_to_enable,
        use_human_readable_error: use_human_readable_error,
        skip_instrumentation: skip_instrumentation
      )
    end

    sig { params(services_list: T::Hash[Symbol, T.class_of(SecurityProduct::Service)]).returns(T::Hash[Symbol, T.class_of(SecurityProduct::Service)]) }
    def enabled_services(services_list = SERVICES)
      services_list.select do |_sym, service|
        service.new(repository).enabled?
      end
    end

    # Advanced Security services have their own special rules for when they are
    # to be enabled, or not, on a given repo. To keep things easier to reason,
    # this method allows us to check which free security services are currently
    # enabled on a given repo.
    sig { returns(T::Hash[Symbol, T.class_of(SecurityProduct::Service)]) }
    def enabled_non_ghas_services
      enabled_services(NON_GHAS_SERVICES)
    end

    # Toggles security products states when a repository is marked as archived.
    sig { params(actor: User).returns(SecurityProduct::Result) }
    def toggle_services_on_repository_marked_as_archived(actor:)
      services = T.let([], T::Array[[Symbol, ServiceOptions]])
      if repository.advanced_security_products_bundled?
        services << [:advanced_security, { force?: true, on_archive?: true }]
      else
        services << [:code_security, { force?: true, on_archive?: true }]
      end

      toggle_services(actor, services_to_disable: services)
    end

    # Toggles security products states based on the current state of repository.
    sig { params(actor: User, services_to_enable: ServiceList).returns(SecurityProduct::Result) }
    def toggle_services_on_repository_state_changed(actor:, services_to_enable: [])
      services_to_disable = []

      # GHAS
      eligible, _ = SecurityProduct::AdvancedSecurity.new(repository).repository_can_enable_ghas?
      if eligible
        if repository.enable_advanced_security_on_state_change?
          services_to_enable << [:advanced_security, { force?: true }]
        else
          services_to_disable << [:advanced_security, { force?: true }]
        end
      end

      # Other services to enable
      toggle_services(actor, services_to_disable: services_to_disable, services_to_enable: services_to_enable)
    end

    # Toggles security products states when a repository owner has changed.
    sig { params(actor: User, previous_owner: User).returns(SecurityProduct::Result) }
    def toggle_services_on_repository_owner_changed(actor:, previous_owner:)
      services_to_disable = []
      services_to_enable = []

      # Always completely disable GHAS for the previous owner
      if repository.advanced_security_products_bundled?
        services_to_disable << [:advanced_security, { force?: true, owner: previous_owner }]
      else
        services_to_disable << [:code_security, { force?: true, owner: previous_owner }]
      end

      # Conditionally enable GHAS if configured/allowed for the new owner
      if repository.enable_advanced_security_on_state_change?
        eligible, _ = SecurityProduct::AdvancedSecurity.new(repository).repository_can_enable_ghas?
        if eligible
          services_to_enable << [:advanced_security, { force?: true, is_repo_transfer: true }]
        end
      end

      toggle_services(actor, services_to_disable: services_to_disable, services_to_enable: services_to_enable)
    end

    private

    sig { params(services_sym_opt: ServiceList).returns(T::Array[[T.class_of(Service), ServiceOptions, Symbol]]) }
    def map_to_services(services_sym_opt)
      services_sym_opt.sort_by do |service_with_options|
        symbol = service_with_options.is_a?(Symbol) ? service_with_options : service_with_options.first
        T.must(SERVICES_SORT_ORDER[symbol])
      end.map do |(sym, opt)|
        [T.must(SERVICES[sym]), opt || {}, sym]
      end
    end

    sig { params(service: SecurityProduct::Service, actor: User, options: ServiceOptions).returns(Result) }
    def enable_service(service, actor:, options: {})
      # Check if the service is currently enabled with the given options as it
      # may require re-enablement if some options have changed.
      if options[:skip_if_enabled] && service.enabled_with_options?(options:)
        return Result.new(ToggledServiceCollection.empty)
      end

      if !options[:force?]
        res = service.can_enable?(actor: actor, options: options)
        return Result.new(ToggledServiceCollection.empty, res.error) if res.error?
      end

      if repository.owner&.security_configurations_enabled?
        repository_security_configuration = RepositorySecurityConfiguration.find_by(repository_id: repository.id)

        if blocked_by_enforced_security_configuration?(Action::Enable, service, options, repository_security_configuration)
          return Result.new(ToggledServiceCollection.empty, :security_configuration_enforced)
        end

        res = service.on_enable(actor: actor, options: options)
        return res if res.error?

        repository_security_configuration&.remove_if_possible(
          action: "enabled", feature: service.to_sym, owner: T.must(repository.owner), action_source: options[:enablement_action]
        )
      else
        res = service.on_enable(actor: actor, options: options)
        return res if res.error?
      end

      res
    end

    sig { params(service: SecurityProduct::Service, actor: User, options: ServiceOptions).returns(Result) }
    def disable_service(service, actor:, options: {})
      if options[:skip_if_disabled] && !service.enabled?
        return Result.new(ToggledServiceCollection.empty)
      end

      if !options[:force?]
        res = service.can_disable?(actor: actor, options: options)
        return Result.new(ToggledServiceCollection.empty, res.error) if res.error?
      end

      if repository.owner&.security_configurations_enabled?
        repository_security_configuration = RepositorySecurityConfiguration.find_by(repository_id: repository.id)

        if blocked_by_enforced_security_configuration?(Action::Disable, service, options, repository_security_configuration)
          return Result.new(ToggledServiceCollection.empty, :security_configuration_enforced)
        end

        res = service.on_disable(actor: actor, options: options)
        return res if res.error?

        repository_security_configuration&.remove_if_possible(
          action: "disabled", feature: service.to_sym, owner: T.must(repository.owner), action_source: options[:enablement_action]
        ) unless service.skip_removing_configuration_on_disable?(options:)
      else
        res = service.on_disable(actor: actor, options: options)
        return res if res.error?
      end

      res
    end

    # This method determines if a service is blocked from being enabled/disabled by the enforced security configuration
    # - A repository security configuration that is not enforced should not block any features from being enabled/disabled
    # - An organization that is not using the security configurations feature as means to manage org enablement
    #   should not block any features from being enabled/disabled
    # - A service/feature that is marked as "not_set" on the enforced configuration should not be blocked from being enabled/disabled
    # - An organization that is using the "default_for_new_(public/private)_repos" defaults on a specific config in addition to enforcing
    #   it should allow new repos that are created to automatically use the enforced configuration
    # - An enterprise admin that is using the enable all/disable all feature should not be blocked from enabling/disabling features
    # - An org admin or security manager should be able to detach from an enforced config if they are making changes from the security configurations page/UI
    # - An org admin or security manager should be able to detach from an enforced config if they are making changes from the security coverage page/UI
    # - Everyone else should be blocked :)
    sig do
      params(
        action: Action,
        service: Service,
        options: ServiceOptions,
        repository_security_configuration: T.nilable(RepositorySecurityConfiguration),
      )
      .returns(T::Boolean)
    end
    def blocked_by_enforced_security_configuration?(action, service, options, repository_security_configuration)
      return false if !repository_security_configuration&.enforced?
      return false if !repository.owner&.security_configurations_enabled?
      return false if options.present? && options[:is_repo_creation]
      return false if options.present? && options[:enablement_action] == "security_configuration_enablement"
      return false if options.present? && options[:enablement_action] == "enterprise_bulk_enablement"
      return false if options.present? && options[:enablement_action] == "security_coverage_page_enablement"
      return false if options.present? && options[:enablement_action] == "secret_assessment_enablement"
      return false if options.present? && options[:enablement_action] == "trial_enablement"
      return false if options.present? && options[:enablement_action] == "trial_reset"
      return false if options.present? && options[:enablement_action] == "ghas_subscription_canceled"
      return false if options.present? && options[:enablement_action] == "sku_unbundling_transition"
      return false if options.present? && options[:on_archive?]
      return false if action == Action::Enable && service.enabled?
      return false if repository_security_configuration.feature_not_set?(service.to_sym)
      return false if !repository.in_organization?

      # If they're trying to disable AutoCodeQL in the context of switching to Advanced Setup,
      # and the configuration allows Advanced Setup, then don't block.
      return false if \
        action == Action::Disable &&
        service.to_sym == :auto_codeql &&
        options[:switching_setup_types] &&
        repository_security_configuration.security_configuration&.code_scanning_general_options&.dig("allow_advanced")

      # By default, this method blocks enablement as well as disablement. This is fine for
      # most services, since if a configuration enforces a feature then that feature will be
      # enabled when the configuration is applied, so you'll never need to enable it.
      # For Code Scanning, however, we could be enforcing it but allowing advanced
      # setup. In that case, default setup (AutoCodeQL) won't be already enabled if
      # they were using advanced setup at the time of enforcement. We don't want to
      # stop them switching to default setup, so we need to explicitly handle this case.
      return false if \
        action == Action::Enable &&
        service.to_sym == :auto_codeql &&
        repository_security_configuration.security_configuration&.code_scanning != "disabled" &&
        repository_security_configuration.security_configuration&.code_scanning_general_options&.dig("allow_advanced")

      true
    end

    sig do
      params(
        actor: T.nilable(User),
        toggled_services: SecurityProduct::ToggledServiceCollection,
        from_services_hash: T::Hash[T.untyped, T.untyped]
      ).void
    end
    def instrument_on_services_toggled(actor, toggled_services, from_services_hash)
      return if toggled_services.empty?

      advanced_security = toggled_services[:advanced_security]
      token_scanning = toggled_services[:token_scanning]
      token_scanning_push_protection = toggled_services[:token_scanning_push_protection]
      code_security = toggled_services[:code_security]

      if advanced_security || token_scanning || token_scanning_push_protection || code_security
        repository.send_security_center_security_feature_repo_update("repo.security_feature_state_toggled")

        # Toggle will run even if enabling already enabled feature
        # We only want to send this event if there are changes
        if from_services_hash != Api::Serializer.serialize(:security_and_analysis_hash, repository)
          GitHub.instrument "security_and_analysis",
            actor_id: actor&.id,
            changes: {
                from: {
                  security_and_analysis: from_services_hash
                }
            },
            repository_id: repository.id
        end
      end
    end
  end
end
