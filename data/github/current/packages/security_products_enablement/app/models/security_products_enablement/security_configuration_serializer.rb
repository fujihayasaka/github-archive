# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class SecurityConfigurationSerializer
    include GitHub::Memoizer

    sig { returns(T.any(User, Business)) }
    attr_accessor :owner

    sig { params(owner: T.any(User, Business)).void }
    def initialize(owner)
      @owner = owner
    end

    sig do
      params(
        security_configuration: T.nilable(SecurityConfiguration),
        details: T::Boolean,
        actor: T.nilable(User),
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def serialize(security_configuration, details: false, actor: nil)
      return {} if security_configuration.nil?

      base = {
        id: security_configuration.id,
        name: security_configuration.name,
        description: security_configuration.description(billable_entity: owner),
        default_for_new_public_repos: defaults_for_owner[:default_for_new_public_repos] == security_configuration.id,
        default_for_new_private_repos: defaults_for_owner[:default_for_new_private_repos] == security_configuration.id,
        enforcement: security_configuration.enforcement(owner),
        enable_ghas: security_configuration.enable_ghas(billable_entity: owner),
        code_security_sku_enabled: security_configuration.code_security_sku_enabled(billable_entity: owner),
        secret_protection_sku_enabled: security_configuration.secret_protection_sku_enabled(billable_entity: owner),
        repositories_count: repositories_count(security_configuration),
      }

      if details
        base.update(
          target_type: security_configuration.target_type,
          private_vulnerability_reporting: security_configuration.private_vulnerability_reporting,
          dependency_graph: security_configuration.dependency_graph,
          dependency_graph_autosubmit_action: security_configuration.dependency_graph_autosubmit_action,
          dependency_graph_autosubmit_action_options: security_configuration.dependency_graph_autosubmit_action_options,
          dependabot_alerts: security_configuration.dependabot_alerts,
          dependabot_security_updates: security_configuration.dependabot_security_updates,
          code_scanning: security_configuration.code_scanning,
          code_scanning_delegated_alert_dismissal: security_configuration.code_scanning_delegated_alert_dismissal,
          code_scanning_options: security_configuration.code_scanning_options,
          secret_scanning: security_configuration.secret_scanning,
          secret_scanning_push_protection: security_configuration.secret_scanning_push_protection,
          secret_scanning_delegated_alert_dismissal: security_configuration.secret_scanning_delegated_alert_dismissal,
        )

        if SecretScanning::Features::Owner::ValidityChecks.new(owner).feature_available?
          base[:secret_scanning_validity_checks] = security_configuration.secret_scanning_validity_checks
        end

        if owner.feature_flag_enabled?(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GENERIC_SECRETS_IN_SECURITY_CONFIGURATIONS, default: true)
          base[:secret_scanning_generic_secrets] = security_configuration.secret_scanning_generic_secrets
        end

        base[:secret_scanning_delegated_bypass] = security_configuration.secret_scanning_delegated_bypass
        if security_configuration.secret_scanning_delegated_bypass == "enabled" && (@owner.is_a?(Organization) || (@owner.is_a?(Business) && SecretScanning::Features::Business::DelegatedBypass.new(@owner).enabled_for_security_configuration?))
          reviewers, err = SecretScanning::Services::DelegatedBypassService.get_bypass_reviewers(@owner, T.must(actor), security_configuration_id: security_configuration.id)
          if err.nil? && !reviewers.nil?
            reviewers_map = reviewers.map do |reviewer|
              SecretScanning::Services::DelegatedBypassService.security_config_bypass_actor_hash(reviewer)
            end
            base[:secret_scanning_delegated_bypass_options] = {
              reviewers: reviewers_map,
            }
          end
        end

        base[:secret_scanning_non_provider_patterns] = security_configuration.secret_scanning_non_provider_patterns
      end
      base
    end

    sig { params(security_configuration: SecurityConfiguration).returns(Integer) }
    def repositories_count(security_configuration)
      ghr = SecurityConfiguration.github_recommended_configuration
      if ghr && security_configuration.id == ghr.id
        github_recommended_configuration_repositories_count
      elsif @owner.is_a? Business
        security_configuration.repository_security_configurations.applied.count
      else
        security_configuration.repository_security_configurations.where(organization_id: @owner.id).applied.count
      end
    end

    sig { params(security_configurations: T::Array[SecurityConfiguration]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def serialize_collection(security_configurations)
      security_configurations.map { |c| serialize(c) }
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    memoize def new_repo_defaults
      output = T.let(
        { newPublicRepoDefaultConfig: nil, newPrivateRepoDefaultConfig: nil },
        {
          newPublicRepoDefaultConfig: T.nilable(T::Hash[Symbol, T.any(String, Integer)]),
          newPrivateRepoDefaultConfig: T.nilable(T::Hash[Symbol, T.any(String, Integer)])
        },
      )
      return output if defaults_for_owner.values.all?(&:nil?)

      config_ids = defaults_for_owner.values

      targets = if @owner.is_a?(Organization)
        [owner, @owner.business].compact
      else
        [owner]
      end

      configurations = SecurityConfiguration \
        .where(target: targets, id: config_ids) # Include configs owned by the org...
        .or(SecurityConfiguration.where(target_type: "global", target_id: 0)) # ...and GitHub recommendations.
        .index_by(&:id)

      defaults_for_owner.each do |type, config_id|
        next if config_id.nil?

        output_type = case type
        when :default_for_new_public_repos then :newPublicRepoDefaultConfig
        when :default_for_new_private_repos then :newPrivateRepoDefaultConfig
        end

        this_config = configurations[config_id]
        # Skip processing if this_config is nil to avoid a NoMethodError.
        next if this_config.nil?

        output[output_type] = { id: this_config.id, name: this_config.name }
      end

      output
    end

    private

    sig { returns(Integer) }
    def github_recommended_configuration_repositories_count
      return 0 unless SecurityConfiguration.github_recommended_configuration

      organization_where = owner.is_a?(Business) ? business_org_ids : owner

      RepositorySecurityConfiguration.applied.where(
        security_configuration_id: SecurityConfiguration.github_recommended_configuration&.id,
        user: organization_where,
      ).count
    end

    sig { returns(T::Hash[Symbol, T.nilable(Integer)]) }
    memoize def defaults_for_owner
      SecurityConfigurationDefault.default_security_configuration_ids_for(owner)
    end

    sig { returns(T::Array[Integer]) }
    memoize def business_org_ids
      raise ArgumentError, "Cannot run method unless owner is a Business!" unless owner.is_a?(Business)

      ActiveRecord::Base.connected_to(role: :reading) do
        owner.organization_ids
      end
    end
  end
end
