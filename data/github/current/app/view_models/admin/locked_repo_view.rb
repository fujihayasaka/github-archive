# typed: true
# frozen_string_literal: true

module Admin
  class LockedRepoView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include GitHub::ResilienceMixin

    attr_reader :current_repository

    # Show a message to GitHubbers letting them know why they can't view this repo.
    #
    # Returns boolean.
    def show_github_repo_message?
      !GitHub.enterprise? && current_user.employee? && github_owned_repo?
    end

    # Does the current repository belong to the GitHub org?
    #
    # Returns boolean.
    def github_owned_repo?
      current_repository.owner == github_org
    end

    # The GitHub organization.
    #
    # Returns an Organization or nil.
    def github_org
      @github_org ||= Organization.find_by_login("github")
    end

    # Can the current user unlock a repository?
    #
    # Returns boolean.
    def show_unlock?
      with_database_error_fallback(fallback: false) do
        current_user.can_unlock_repos?
      end
    end
  end
end
