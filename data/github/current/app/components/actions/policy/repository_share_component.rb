# typed: true
# frozen_string_literal: true

module Actions
  module Policy
    class RepositoryShareComponent < ApplicationComponent
      def initialize(repo:, action:)
        @repo = repo
        @action = action
      end

      def render?
        return false unless @repo.private?
        return true if is_repo_internal?
        true
      end

      def self.options(owner_name, business_name, is_owner_organization, is_repo_internal)
        allowed_repos = is_repo_internal ? "private or internal" : "private"

        if business_name.present?
          [
                  {
                    value: Configurable::ActionsRepositorySharePolicy::NONE,
                    text: "Not accessible",
                    description: "Workflows in other repositories cannot access this repository."
                  },
                  {
                    value: Configurable::ActionsRepositorySharePolicy::ACCESSIBLE_SAME_ORGANIZATION,
                    text: "Accessible from repositories in the '#{owner_name}' organization",
                    description: "Workflows in other repositories that are part of the '#{owner_name}' organization can access the actions and reusable workflows in this repository. Access is allowed only from #{allowed_repos} repositories."
                  },
                  {
                    value: Configurable::ActionsRepositorySharePolicy::ACCESSIBLE_SAME_BUSINESS,
                    text: "Accessible from repositories in the '#{business_name}' enterprise",
                    description: "Workflows in other repositories that are part of the '#{business_name}' enterprise can access the actions and reusable workflows in this repository. Access is allowed only from #{allowed_repos} repositories."
                  }
                ]
        elsif is_owner_organization
          [
                  {
                    value: Configurable::ActionsRepositorySharePolicy::NONE,
                    text: "Not accessible",
                    description: "Workflows in other repositories cannot access this repository."
                  },
                  {
                    value: Configurable::ActionsRepositorySharePolicy::ACCESSIBLE_SAME_ORGANIZATION,
                    text: "Accessible from repositories in the '#{owner_name}' organization",
                    description: "Workflows in other repositories that are part of the '#{owner_name}' organization can access the actions and reusable workflows in this repository. Access is allowed only from private repositories."
                  }
                ]
        else
          [
                  {
                    value: Configurable::ActionsRepositorySharePolicy::NONE,
                    text: "Not accessible",
                    description: "Workflows in other repositories cannot access this repository."
                  },
                  {
                    value: Configurable::ActionsRepositorySharePolicy::ACCESSIBLE_SAME_USER,
                    text: "Accessible from repositories owned by the user '#{owner_name}'",
                    description: "Workflows in other repositories that are owned by the user '#{owner_name}' can access the actions and reusable workflows in this repository. Access is allowed only from private repositories."
                  }
                ]
        end
      end

      memoize def effective_policy
        @repo.actions_repository_share_policy
      end

      memoize def owner_name
        @repo.owner&.display_login || ""
      end

      memoize def business_name
        @repo.owner&.business&.name || ""
      end

      def is_owner_organization?
        @repo.owner&.organization?
      end

      def is_repo_internal?
        @repo.internal?
      end
    end
  end
end
