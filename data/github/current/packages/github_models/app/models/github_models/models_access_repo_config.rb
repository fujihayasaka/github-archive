# typed: strict
# frozen_string_literal: true

module GitHubModels
  class ModelsAccessRepoConfig
    include ::Configurable
    include ::Configurable::ModelsAccess

    sig { returns(String) }
    def configuration_entry_type
      T.must(::Repository.name)
    end

    # Leverage the repository's cached config
    sig { returns(Configuration) }
    def config
      T.cast(repository, ::Repository).config # rubocop:todo GitHub/AvoidCast
    end

    sig { returns(Repositories::IRepository) }
    attr_reader :repository

    sig { params(repository: Repositories::IRepository).void }
    def initialize(repository)
      @repository = repository
    end

    # Public: Overrides Configurable::ModelsAccess#instrument_github_models_enablement
    sig { params(actor: ::User).void }
    def instrument_github_models_enablement(actor:)
      repo = T.cast(repository, ::Repository) # rubocop:todo GitHub/AvoidCast

      # Audit log:
      repo.instrument(:github_models_enabled, actor: actor)
    end

    # Public: Overrides Configurable::ModelsAccess#instrument_github_models_disablement
    sig { params(actor: ::User).void }
    def instrument_github_models_disablement(actor:)
      repo = T.cast(repository, ::Repository) # rubocop:todo GitHub/AvoidCast

      # Audit log:
      repo.instrument(:github_models_disabled, actor: actor)
    end

    # Public: Overrides Configurable::ModelsAccess#default_enabled_status
    sig { returns T::Boolean }
    def default_enabled_status
      return false if repository.public? # public repos default to Models off

      organization = self.organization
      return false unless organization # user-owned repos default to Models off

      # If the org has Models turned on, default the org's repos to having Models on:
      org_policy = GitHubModels::OrganizationAccessPolicy.new(org: organization)
      org_policy.models_enabled_for_org?
    end

    sig { returns T::Boolean }
    def models_access_enabled?
      return false if repository.owner.nil?

      if repository.owner&.organization?
        return false unless T.cast(repository.owner, ::Organization).models_access_enabled?
      end

      value = ::Configuration::Entry.targeting_repository_ids(repository.id).named(::Configurable::ModelsAccess::KEY).first&.value

      # For user owned repos, models access is disabled by default
      # For org owned repos, models access is enabled by default
      return true if value.nil? && repository.owner&.organization?

      ActiveModel::Type::Boolean.new.cast(value) || false
    end

    private

    sig { returns T.nilable(::Organization) }
    def organization
      repo_owner = repository.owner
      repo_owner&.organization? ? T.cast(repo_owner, ::Organization) : nil
    end
  end
end
