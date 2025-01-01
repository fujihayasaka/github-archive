# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  class SecurityConfigurationSerializer
    extend T::Sig
    include GitHub::Memoizer

    DETAILED_ATTRIBUTES = T.let(%i(
      target_type
      private_vulnerability_reporting
      dependency_graph
      dependency_graph_autosubmit_action
      dependency_graph_autosubmit_action_options
      dependabot_alerts
      dependabot_security_updates
      code_scanning
      secret_scanning
      secret_scanning_push_protection), T::Array[Symbol])

    attr_accessor :organization

    sig { params(organization: Organization).void }
    def initialize(organization)
      @organization = organization
    end

    sig { params(security_configuration: T.nilable(SecurityConfiguration), details: T::Boolean).returns(Hash) }
    def serialize(security_configuration, details: false)
      return {} if security_configuration.nil?

      base = {
        id: security_configuration.id,
        name: security_configuration.name,
        description: security_configuration.description,
        default_for_new_public_repos: defaults_for_org.detect do |d|
          d.default_for_new_public_repos && d.security_configuration_id == security_configuration.id
        end.present?,
        default_for_new_private_repos: defaults_for_org.detect do |d|
          d.default_for_new_private_repos && d.security_configuration_id == security_configuration.id
        end.present?,
        enforcement: security_configuration.enforcement(organization),
      }

      if details
        DETAILED_ATTRIBUTES.each { |attr| base[attr] = security_configuration.send(attr) } # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod

        if organization.feature_enabled?(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS)
          base[:secret_scanning_validity_checks] = security_configuration.secret_scanning_validity_checks
        end

        base[:secret_scanning_non_provider_patterns] = security_configuration.secret_scanning_non_provider_patterns
      end

      if SecurityConfiguration.github_recommended_configuration && security_configuration.id == SecurityConfiguration.github_recommended_configuration&.id
        base.merge!({
          enable_ghas: true,
          repositories_count: github_recommended_configuration_repositories_count
        })
      else
        base.merge!({
          enable_ghas: security_configuration.enable_ghas,
          repositories_count: security_configuration.repositories_count
        })
      end

      base
    end

    sig { params(security_configurations: T::Array[SecurityConfiguration]).returns(T::Array[Hash]) }
    def serialize_collection(security_configurations)
      security_configurations.map { |c| serialize(c) }
    end

    memoize def new_repo_defaults
      output = T.let(
        { newPublicRepoDefaultConfig: nil, newPrivateRepoDefaultConfig: nil },
        {
          newPublicRepoDefaultConfig: T.nilable(T::Hash[Symbol, T.any(String, Integer)]),
          newPrivateRepoDefaultConfig: T.nilable(T::Hash[Symbol, T.any(String, Integer)])
        },
      )
      return output if defaults_for_org.blank?

      config_ids = defaults_for_org.collect(&:security_configuration_id)
      configurations = SecurityConfiguration \
        .where(target: organization, id: config_ids) # Include configs owned by the org...
        .or(SecurityConfiguration.where(target_type: "global", target_id: 0)) # ...and GitHub recommendations.
        .index_by(&:id)

      defaults_for_org.each do |default|
        this_config = configurations[default.security_configuration_id]
        config_output = { id: this_config.id, name: this_config.name }

        output[:newPublicRepoDefaultConfig] = config_output if default.default_for_new_public_repos
        output[:newPrivateRepoDefaultConfig] = config_output if default.default_for_new_private_repos
      end

      output
    end

    private

    sig { returns(Integer) }
    def github_recommended_configuration_repositories_count
      return 0 unless SecurityConfiguration.github_recommended_configuration

      RepositorySecurityConfiguration.applied.where(
        security_configuration_id: SecurityConfiguration.github_recommended_configuration&.id,
        organization: organization,
      ).count
    end

    memoize def defaults_for_org
      SecurityConfigurationDefault.where(target: organization).to_a
    end
  end
end
