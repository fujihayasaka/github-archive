# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class SecurityConfigurationSerializer
    include GitHub::Memoizer

    # Encapsulates repository state counts for a security configuration
    class StateCounts
      sig { params(counts: T::Hash[RepositorySecurityConfiguration::State, Integer]).void }
      def initialize(counts)
        @counts = counts
      end

      sig { params(states: RepositorySecurityConfiguration::State).returns(Integer) }
      def count_for(*states)
        states.sum { |state| @counts[state] || 0 }
      end

      sig { params(state: Symbol, count: Integer).void }
      def set_count(state, count)
        @counts[RepositorySecurityConfiguration::State.deserialize(state)] = count
      end
    end

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
        state_counts: T.nilable(StateCounts),
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def serialize(security_configuration, details: false, actor: nil, state_counts: nil)
      return {} if security_configuration.nil?

      state_counts ||= repo_counts_grouped_by_state(security_configuration)

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
        repositories_count: state_counts.count_for(RepositorySecurityConfiguration::State::Attached, RepositorySecurityConfiguration::State::Enforced),
      }

      if FeatureFlag.vexi.enabled?(:security_configs_quick_set_up, @owner, default: false)
        base[:failed_repos_count] = state_counts.count_for(RepositorySecurityConfiguration::State::Failed)
        base[:removed_repos_count] = state_counts.count_for(RepositorySecurityConfiguration::State::Removed, RepositorySecurityConfiguration::State::RemovedByEnterprise)
      end

      if details
        base.update(
          target_type: security_configuration.target_type,
          private_vulnerability_reporting: security_configuration.private_vulnerability_reporting,
          dependency_graph: security_configuration.dependency_graph,
          dependency_graph_autosubmit_action: security_configuration.dependency_graph_autosubmit_action,
          dependency_graph_autosubmit_action_options: security_configuration.dependency_graph_autosubmit_action_options,
          dependabot_alerts: security_configuration.dependabot_alerts,
          dependabot_security_updates: security_configuration.dependabot_security_updates,
          dependabot_delegated_alert_dismissal: security_configuration.dependabot_delegated_alert_dismissal,
          dependabot_malware_alerts: serialize_dependabot_malware_alerts(security_configuration),
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

        if owner.feature_flag_enabled?(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::EXTENDED_METADATA_CONFIGURABLE_IN_SECURITY_CONFIGS, default: false)
          base[:secret_scanning_extended_metadata] = security_configuration.secret_scanning_extended_metadata
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
      state_counts = repo_counts_grouped_by_state(security_configuration)
      state_counts.count_for(RepositorySecurityConfiguration::State::Attached, RepositorySecurityConfiguration::State::Enforced)
    end

    sig { params(security_configurations: T::Array[SecurityConfiguration]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def serialize_collection(security_configurations)
      all_counts = batch_repo_counts_grouped_by_state(security_configurations)
      security_configurations.map { |c| serialize(c, state_counts: all_counts[c.id] || StateCounts.new({})) }
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

    sig { params(security_configuration: SecurityConfiguration).returns(StateCounts) }
    def repo_counts_grouped_by_state(security_configuration)
      batch_repo_counts_grouped_by_state([security_configuration])[security_configuration.id] || StateCounts.new({})
    end

    # Returns a hash of { config_id => StateCounts } for all given configurations in a single query
    sig { params(security_configurations: T::Array[SecurityConfiguration]).returns(T::Hash[Integer, StateCounts]) }
    def batch_repo_counts_grouped_by_state(security_configurations)
      return {} if security_configurations.empty?

      config_ids = security_configurations.map(&:id)
      ghr = SecurityConfiguration.github_recommended_configuration
      ghr_id = ghr&.id

      # Build the base query using the for_owner scope
      base_query = RepositorySecurityConfiguration
        .where(security_configuration_id: config_ids)
        .for_owner(@owner)

      # Handle GitHub recommended config separately if present (uses `user` column instead of `organization_id`)
      if ghr_id && config_ids.include?(ghr_id)
        organization_where = owner.is_a?(Business) ? business_org_ids : owner
        ghr_query = RepositorySecurityConfiguration.where(
          security_configuration_id: ghr_id,
          user: organization_where,
        )
        # Union the queries for GHR and non-GHR configs
        non_ghr_config_ids = config_ids - [ghr_id]
        if non_ghr_config_ids.any?
          non_ghr_query = RepositorySecurityConfiguration
            .where(security_configuration_id: non_ghr_config_ids)
            .for_owner(@owner)
          base_query = ghr_query.or(non_ghr_query)
        else
          base_query = ghr_query
        end
      end

      # Group by config_id and state, get counts
      raw_counts = base_query.group(:security_configuration_id, :state).count

      # Transform into hash of StateCounts: { config_id => StateCounts }
      counts_by_config = T.let({}, T::Hash[Integer, StateCounts])
      raw_counts.each do |(config_id, state_str), count|
        state_count = counts_by_config[config_id] ||= StateCounts.new({})
        state_count.set_count(state_str.to_sym, count)
      end

      counts_by_config
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

    sig { params(security_configuration: SecurityConfiguration).returns(String) }
    def serialize_dependabot_malware_alerts(security_configuration)
      # When the feature flag is off, the feature is unavailable so we show "disabled" to the UI
      return "disabled" unless FeatureFlag.vexi.enabled?("dependabot_allow_malware_frontend", owner, default: false)

      security_configuration.dependabot_malware_alerts
    end
  end
end
