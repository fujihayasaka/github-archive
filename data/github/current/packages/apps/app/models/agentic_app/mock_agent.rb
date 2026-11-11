# typed: strict
# frozen_string_literal: true

module AgenticApp
  # MockAgent is a lightweight adapter that wraps an Integration and exposes the
  # AgenticApp interface. It enables tests to register ad-hoc privileged apps
  # without creating dedicated subclasses.
  class MockAgent
    include ::AgenticApp

    sig { params(integration: Integration).void }
    def initialize(integration)
      @integration = T.let(integration, Integration)
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
    def doc_url
      "https://docs.github.com/en/copilot"
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
      capability?(:is_assignable)
    end

    sig { override.returns(T::Boolean) }
    def mentionable?
      capability?(:pr_autocomplete_mentionable)
    end

    sig { override.returns(T::Boolean) }
    def global?
      capability?(:installed_globally)
    end

    sig { override.params(target: T.any(User, Organization, Business)).returns(T::Boolean) }
    def installed_for_target?(target)
      return true if global?
      return false if @integration.destroyed?

      @integration.installed_on?(target)
    rescue StandardError
      false
    end

    sig { override.params(target: T.any(User, Organization, Business)).returns(T::Boolean) }
    def can_be_enabled_for?(target)
      return true if global?
      return false if @integration.destroyed?
      return true if installed_for_target?(target)

      IntegrationInstallTrigger.where(
        integration: @integration,
        install_type: IntegrationInstallTrigger.install_types[:third_party_agents_enabled],
        deactivated: false,
      ).exists?
    rescue StandardError
      true
    end

    sig do
      override.params(
        repo: T.untyped,
        viewer: T.untyped
      ).returns(T::Boolean)
    end
    def enabled_for_repository?(repo, viewer)
      return false if @integration.destroyed?
      return false unless AgenticApp.enterprise_opted_in?(self, repo.owner)

      if global?
        assignable?
      else
        installation = IntegrationInstallation.with_target(repo.owner).find_by(integration: @integration)
        return false if installation.nil?

        installed_repo_ids = installation.repository_ids(resource: "metadata", repository_ids: [repo.id])
        installed_repo_ids.include?(repo.id)
      end
    end

    private

    sig { params(capability: Symbol).returns(T::Boolean) }
    def capability?(capability)
      Apps::Privileged.capable?(capability, app: @integration)
    rescue StandardError
      false
    end
  end
end
