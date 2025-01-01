# typed: strict
# frozen_string_literal: true

# Public: Configures whether to use a repo's `.github/FUNDING.md` file to display a Sponsor button on the repo page.
module Configurable
  module RepositoryFundingLinks
    extend Configurable::Async
    extend T::Helpers
    extend T::Sig

    requires_ancestor { Configurable }

    KEY = T.let("repository_funding_links".freeze, String)

    # Public: Enable repository funding links for the repository or organization
    sig { params(actor: T.nilable(User)).void }
    def enable_repository_funding_links(actor:)
      T.bind(self, Repository)
      return if repository_funding_links_explicitly_enabled?

      config.enable(KEY, actor)

      if GitHub.sponsors_enabled?
        UpdateRepositorySponsorablesForRepositoryJob.perform_later(repository_id: id)
        if global_health_files_repository?
          UpdateRepositorySponsorablesForGlobalRepoJob.perform_later(repository_id: id)
        end
      end

      GlobalInstrumenter.instrument("sponsors.repo_funding_links_button_toggle", {
        repository: self,
        actor: actor,
        owner: owner,
        toggle_state: "ENABLED",
      })
    end

    # Public: Disable repository funding links for the repository or organization
    sig { params(actor: T.nilable(User)).void }
    def disable_repository_funding_links(actor:)
      T.bind(self, Repository)
      return if repository_funding_links_explicitly_disabled?

      config.disable(KEY, actor)

      if GitHub.sponsors_enabled?
        UpdateRepositorySponsorablesForRepositoryJob.perform_later(repository_id: id)
        if global_health_files_repository?
          UpdateRepositorySponsorablesForGlobalRepoJob.perform_later(repository_id: id)
        end
      end

      GlobalInstrumenter.instrument("sponsors.repo_funding_links_button_toggle", {
        repository: self,
        actor: actor,
        owner: owner,
        toggle_state: "DISABLED",
      })
    end

    # Public: Determine whether repository funding links are explicitly enabled
    sig { returns T::Boolean }
    def repository_funding_links_explicitly_enabled?
      config.enabled?(KEY)
    end
    async_configurable :repository_funding_links_explicitly_enabled?

    # Public: Determine whether repository funding links are explicitly disabled
    sig { returns T::Boolean }
    def repository_funding_links_explicitly_disabled?
      config.get(KEY) == false
    end

    # Public: Determine if repository funding links have neither been explicitly set or unset
    sig { returns T::Boolean }
    def repository_funding_links_unset?
      config.get(KEY).nil?
    end
    async_configurable :repository_funding_links_unset?
  end
end
