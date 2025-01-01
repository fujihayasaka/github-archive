# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class UpdateTrustedRepositoryAccess < Codespaces::Command

    class InvalidExtendedRepoConfiguration < StandardError; end
    class RepositoryNotOwned < StandardError; end

    # Codespaces::Command can't specify default parameterized args
    def self.call(actor:, target:, trusted_repo_setting: nil, repo: nil, entry_point:)
      super
    end

    attr_reader :actor, :target, :trusted_repo_setting, :repo, :installation, :entry_point

    def initialize(actor:, target:, trusted_repo_setting:, repo:, entry_point:)
      @actor, @target, @trusted_repo_setting, @repo, @entry_point = actor, target, trusted_repo_setting, repo, entry_point
      @installation = target.integration_installations.find_by(integration: codespaces_integration)
    end

    # Public: checks the value of target.codespace_trusted_repositories_access (defined in Configurable::CodespaceTrustedRepositories)
    # and does one of three things:
    #
    # ALL_REPOS: creates or updates the :codespaces_integration installation and grants access to codespaces for all of
    #            `target`'s repos.
    # DISABLED: removes any access granted to the :codespaces_integration installation
    # SELECTED_REPOS: adds `repository_ids` to the trusted repos list
    #
    # Raises Configurable::CodespaceTrustedRepositories::RepositoryNotOwned if `target` does not own the `repo`
    #
    # Raises Configurable::CodespaceTrustedRepositories::InvalidRepoAccessArgumentError if an
    # invalid `trusted_repo_setting` is passed
    #
    def perform
      # target must own the repository if a `repo` is being added or removed
      raise RepositoryNotOwned.new unless target_repository.present? if repo

      ActiveRecord::Base.connected_to(role: :writing) do
        target.update_codespace_trusted_repositories_access(trusted_repo_setting, actor: actor) unless trusted_repo_setting.blank?

        case target.codespace_trusted_repositories_access
        when Configurable::CodespaceTrustedRepositories::ALL_REPOS
          # An empty array defaults to all repositories owned by the target
          installation&.edit(repositories: [], editor: actor, entry_point: entry_point) if access_changed?
          create_integration_installation(repositories: []) if installation.blank?

        when Configurable::CodespaceTrustedRepositories::SELECTED_REPOS
          # if no installation or access_changed? then we need to remove/re-create the installation
          if installation.blank? || access_changed?
            # in order to reset any previously configured settings/repos we need to remove/re-create the installation
            installation&.uninstall

            # create a new integration installation
            create_integration_installation(
              # when first enabling SELECTED_REPOS we need to pass :none here if target_repository is blank
              repositories: (target_repository.blank? ? :none : Array(target_repository))
            )
          else
            # toggle a repository to be trusted or not trusted
            action = installation.repository_ids(repository_ids: Array(target_repository&.id)).any? ? :remove : :add

            IntegrationInstallation::RepositoryEditor.perform(
              installation,
              # if `repo` is already trusted, make it un-trusted
              action: action,
              # if target_repository.blank? the user likely _just enabled the feature_ and hasn't chosen any repos  yet
              repositories: Array(target_repository),
              editor: actor,
              entry_point: entry_point
            )
          end
        when Configurable::CodespaceTrustedRepositories::DISABLED
          installation&.uninstall
        end
      end
    end

    private

    def access_changed?
      case installation&.repository_selection
      when "selected"
        target.codespace_trusted_repositories_access != Configurable::CodespaceTrustedRepositories::SELECTED_REPOS
      when "all"
        target.codespace_trusted_repositories_access != Configurable::CodespaceTrustedRepositories::ALL_REPOS
      else
        # assume access_changed? => true. worst case scenario is we'll do extra bookkeeping removing, then re-creating
        # installations for the :codespaces_integration. if we're here `installation` is probably `nil`
        true
      end
    end

    def create_integration_installation(repositories: Array(target_repository))
      IntegrationInstallation::Creator.perform(
        codespaces_integration,
        target,
        installer: actor,
        repositories: repositories,
        version: codespaces_integration.latest_version,
        entry_point: entry_point
      )
    end

    def codespaces_integration
      Apps::Internal.integration(:codespaces_production)
    end

    def target_repository
      target.repositories.find_by(id: repo)
    end
  end
end
