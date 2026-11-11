# typed: strict
# frozen_string_literal: true

module AgenticApp
  # Base class for all agentic apps (AI coding agents).
  #
  # This class will evolve into an ActiveRecord model in the near future.
  # For now, it extracts shared behavior from partner agents (Claude, Codex)
  # while providing extension points for global agents (Copilot).
  #
  # Subclasses must implement configuration methods that will eventually
  # be replaced by database columns.
  class Base
    extend T::Helpers

    include ::AgenticApp
    include Singleton

    abstract!

    # Configuration methods - to be replaced by DB columns in AR migration

    sig { abstract.returns(Symbol) }
    def privileged_app_alias; end

    sig { abstract.returns(Symbol) }
    def disallow_feature_flag; end

    sig { abstract.returns(Symbol) }
    def policy_feature_flag; end

    # AgenticApp interface implementation

    sig { override.returns(String) }
    def mention_slug
      display_name.downcase
    end

    sig { override.returns(T.nilable(String)) }
    def model_vendor
      nil
    end

    sig { override.returns(T::Array[String]) }
    def model_vendors
      []
    end

    sig { override.returns(T.nilable(Integration)) }
    def integration
      if FeatureFlag.vexi.enabled?(:agentic_app_lookup_optimization, default: false)
        cache = AgenticApp::RequestCache.integrations ||= {}
        key = privileged_app_alias
        return T.cast(cache[key], T.nilable(Integration)) if cache.key?(key)

        return cache[key] = Apps::Privileged.integration(key)
      end

      Apps::Privileged.integration(privileged_app_alias)
    end

    sig { override.returns(String) }
    def commit_email
      "#{bot_id}+#{display_name}@#{GitHub.stealth_email_host_name}"
    end

    sig { override.returns(T.nilable(Integer)) }
    def bot_id
      integration&.bot_id
    end

    sig { override.returns(T::Boolean) }
    def assignable?
      return false unless integration
      true
    end

    sig { override.returns(T::Boolean) }
    def mentionable?
      return false unless integration
      true
    end

    sig { override.returns(T::Boolean) }
    def global?
      false
    end

    sig { override.returns(T::Boolean) }
    def partner_agent?
      false
    end

    sig { override.returns(AgenticApp::Group) }
    def group
      AgenticApp::Group::CLOUD
    end

    sig { override.returns(T::Boolean) }
    def finished_notifications_enabled?
      false
    end

    sig { override.params(target: T.any(User, Organization, Business)).returns(T::Boolean) }
    def installed_for_target?(target)
      integration&.installed_on?(target) || false
    end

    sig { override.params(target: T.any(User, Organization, Business)).returns(T::Boolean) }
    def can_be_enabled_for?(target)
      return false unless integration
      return false unless AgenticApp.enterprise_opted_in?(self, target)
      return false if target.is_a?(User) && Copilot::User.new(target).has_limited_access?

      business = target.is_a?(Business) ? target : AgenticApp.business_for(target)
      return false if disallow_flag_enabled?(business)
      return false if disallow_flag_enabled?(target)

      if business
        return true if business.feature_flag_enabled?(policy_feature_flag, default: false)
      end

      target.feature_flag_enabled?(policy_feature_flag, default: false)
    end

    sig do
      override.params(
        repo: T.untyped,
        viewer: T.untyped
      ).returns(T::Boolean)
    end
    def enabled_for_repository?(repo, viewer)
      installation = installation_for_repository(integration, repo)

      feature_flag_enabled?(repo) &&
        !restricted_by_policies?(repo, viewer) &&
        installed_on_repository?(installation, repo) &&
        admin_agentic_consent?(integration, installation, viewer)
    end

    sig { override.returns(T::Boolean) }
    def require_workflow_approval_for_prs?
      Apps::Privileged.capable?(:actions_require_workflow_approval, app: integration)
    end

    private

    sig { params(repo: T.untyped).returns(T::Boolean) }
    def feature_flag_enabled?(repo)
      return false if disallow_flag_enabled?(repo)

      business = AgenticApp.business_for(repo.owner)
      return false if disallow_flag_enabled?(business)

      if business
        return true if business.feature_flag_enabled?(policy_feature_flag, default: false)
      end

      owner = repo.owner
      return false if disallow_flag_enabled?(owner)

      repo.feature_flag_enabled?(policy_feature_flag, default: false) ||
        owner&.feature_flag_enabled?(policy_feature_flag, default: false)
    end

    sig { params(installation: T.nilable(IntegrationInstallation), repo: T.untyped).returns(T::Boolean) }
    def installed_on_repository?(installation, repo)
      return false unless installation

      installed_repo_ids = installation.repository_ids(resource: "metadata", repository_ids: [repo.id])

      installed_repo_ids.include?(repo.id)
    end

    sig do
      params(
        integration: T.nilable(Integration),
        installation: T.nilable(IntegrationInstallation),
        viewer: T.untyped,
      ).returns(T::Boolean)
    end
    def admin_agentic_consent?(integration, installation, viewer)
      if FeatureFlag.vexi.enabled?(:agentic_app_install_consent_check, viewer, default: false)
        return true if integration.nil?
        return true unless Copilot::IntegrationAgentSource.exists?(integration: integration)
        return true unless installation
        return installation.agent_consent.present?
      end

      true
    end

    sig { params(integration: T.nilable(Integration), repo: T.untyped).returns(T.nilable(IntegrationInstallation)) }
    def installation_for_repository(integration, repo)
      return nil if integration.nil?

      owner = repo.owner
      cache = AgenticApp::RequestCache.integration_installations ||= {}
      key = [integration.id, owner.class.name, owner.id]
      return T.cast(cache[key], T.nilable(IntegrationInstallation)) if cache.key?(key)

      cache[key] = IntegrationInstallation.with_target(owner).find_by(integration: integration)
    end

    sig { params(repo: T.untyped, viewer: T.untyped).returns(T::Boolean) }
    def restricted_by_policies?(repo, viewer)
      return false if viewer&.id == bot_id # the agent should never be restricted

      if !repo.owner&.copilot_swe_agent_enabled_for?(repo) # For now, we want to restrict agents to only work if CCA is also enabled
        true
      elsif repo.owner.is_a?(Organization) && !installed_for_target?(repo.owner)
        true
      elsif !AgenticApp.enterprise_opted_in?(self, repo.owner) # check enterprise policy
        true
      elsif !AgenticApp.has_copilot_enterprise_license?(repo.owner) # check Copilot Enterprise license
        true
      else
        false
      end
    end

    sig { params(flaggable: T.untyped).returns(T::Boolean) }
    def disallow_flag_enabled?(flaggable)
      return false if flaggable.nil?

      return true if flaggable.feature_flag_enabled?(disallow_feature_flag, default: false)

      # 3p agents must also respect the copilot_swe_agent_disallow flag,
      # which blocks all AI coding agents from a repository for security reasons.
      if disallow_feature_flag != :copilot_swe_agent_disallow
        return true if flaggable.feature_flag_enabled?(:copilot_swe_agent_disallow, default: false)
      end

      false
    end
  end
end
