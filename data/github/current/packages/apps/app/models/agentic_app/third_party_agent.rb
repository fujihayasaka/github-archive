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
      @repository = T.let(T.must(agent_source.repository), Repositories::IRepository)
    end

    sig { override.returns(String) }
    def slug
      @integration.slug
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
      "#{bot_id}+#{slug}@users.noreply.github.com"
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

      installation = IntegrationInstallation.with_target(repo.owner).find_by(integration: @integration)
      return false if installation.nil?

      installation.repository_ids(repository_ids: [repo.id], resource: "metadata").include?(repo.id)
    end

    sig { returns(String) }
    def repository_url
      @repository.permalink
    end
  end
end
