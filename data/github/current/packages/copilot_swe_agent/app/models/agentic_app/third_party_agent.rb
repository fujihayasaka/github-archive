# typed: strict
# frozen_string_literal: true

module AgenticApp
  # ThirdPartyAgent is a production adapter that wraps a
  # Copilot::IntegrationAgentSource (and its associated Integration) and
  # exposes the AgenticApp interface.  This bridges data-driven (v2) agents
  # stored in the database into the same registry used by hardcoded (v1)
  # singleton agents.
  class ThirdPartyAgent
    include ::AgenticApp

    sig { returns(Copilot::IntegrationAgentSource) }
    attr_reader :agent_source

    sig { params(agent_source: Copilot::IntegrationAgentSource).void }
    def initialize(agent_source)
      @agent_source = T.let(agent_source, Copilot::IntegrationAgentSource)
      @integration = T.let(T.must(agent_source.integration), Integration)
    end

    sig { override.returns(String) }
    def slug
      @integration.slug
    end

    sig { override.returns(String) }
    def mention_slug
      slug
    end

    sig { override.returns(String) }
    def display_name
      @integration.name
    end

    sig { override.returns(String) }
    def display_owner
      @integration.owner&.display_login || "Unknown"
    end

    sig { override.returns(String) }
    def commit_email
      "#{bot_id}+#{slug}@#{GitHub.stealth_email_host_name}"
    end

    sig { override.returns(T.nilable(String)) }
    def model_vendor
      nil
    end

    sig { override.returns(T::Array[String]) }
    def model_vendors
      @agent_source.model_vendors || []
    end

    sig { override.returns(String) }
    def doc_url
      @integration.url || ""
    end

    sig { override.returns(Integration) }
    def integration
      @integration
    end

    sig { override.returns(T.nilable(Integer)) }
    def bot_id
      @integration.bot_id
    end

    sig { override.returns(T::Boolean) }
    def assignable?
      true
    end

    sig { override.returns(T::Boolean) }
    def mentionable?
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
      return false if @integration.destroyed?

      @integration.installed_on?(target)
    end

    sig { override.params(target: T.any(User, Organization, Business)).returns(T::Boolean) }
    def can_be_enabled_for?(target)
      return false if @integration.destroyed?
      installed_for_target?(target)
    end

    sig do
      override.params(
        repo: T.untyped,
        viewer: T.untyped
      ).returns(T::Boolean)
    end
    def enabled_for_repository?(repo, viewer)
      return false if @integration.destroyed?
      return false unless cca_agentic_github_apps_allowed?(repo)

      # If CCA isn't available to the viewer or isn't enabled on the
      # repository, the agentic app must not be surfaced in the issue
      # assignee picker, @mention autocomplete, etc.
      #
      # We bypass this check when the viewer is this agent's own bot to
      # avoid recursing back into `enabled_for_repository?` via
      # `Repository#copilot_swe_agent_enabled?`
      unless viewer.is_a?(Bot) && viewer.id == bot_id
        return false unless repo.copilot_swe_agent_enabled?(viewer)
      end

      installation = IntegrationInstallation.with_target(repo.owner).find_by(integration: @integration)
      return false if installation.nil?
      return false unless installation.repository_ids(repository_ids: [repo.id], resource: "metadata").include?(repo.id)
      return false unless admin_agentic_consent?(@integration, installation, viewer)

      true
    end

    sig { override.returns(T::Boolean) }
    def require_workflow_approval_for_prs?
      true
    end

    private

    sig { params(repo: T.untyped).returns(T::Boolean) }
    def cca_agentic_github_apps_allowed?(repo)
      if repo.owner.is_a?(Organization)
        copilot_organization = Copilot::Organization.new(repo.owner)
        if Copilot::Policies::CcaAgenticGitHubApps.available_for?(copilot_organization)
          return Copilot::Policies::CcaAgenticGitHubApps.enabled?(copilot_organization)
        end
      end

      business = AgenticApp.business_for(repo.owner)
      return true unless business

      copilot_business = Copilot::Business.new(business)
      return true unless Copilot::Policies::CcaAgenticGitHubApps.available_for?(copilot_business)

      Copilot::Policies::CcaAgenticGitHubApps.enabled?(copilot_business)
    end

    sig { params(integration: T.nilable(Integration), installation: T.nilable(IntegrationInstallation), viewer: T.untyped).returns(T::Boolean) }
    def admin_agentic_consent?(integration, installation, viewer)
      if FeatureFlag.vexi.enabled?(:agentic_app_install_consent_check, viewer, default: false)
        return true if integration.nil?
        return true unless Copilot::IntegrationAgentSource.exists?(integration: integration)
        return true unless installation
        return installation.agent_consent.present?
      end

      true
    end
  end
end
