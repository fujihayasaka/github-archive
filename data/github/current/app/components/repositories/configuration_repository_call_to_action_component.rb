# typed: true
# frozen_string_literal: true

module Repositories
  class ConfigurationRepositoryCallToActionComponent < ApplicationComponent
    attr_reader :org_profile_readme
    attr_reader :org_member_profile_readme
    attr_reader :repository
    attr_reader :tree_name
    attr_reader :user

    def initialize(user:, repository:, tree_name: nil)
      @user = user
      @repository = repository
      @tree_name = tree_name || repository.default_branch

      @private = repository.private?
      @org_profile_readme = organization? && repository.org_profile_readme
      @org_member_profile_readme = org_member_profile? && repository.org_member_profile_readme
    end

    memoize def readme
      if !organization?
        repository.preferred_readme
      elsif org_member_profile?
        org_member_profile_readme
      else
        org_profile_readme
      end
    end

    def private?
      @private
    end

    memoize def opted_in?
      if organization?
        # there's no opt-in process for orgs
        true
      else
        user&.profile_readme_opt_in?
      end
    end

    memoize def organization?
      repository.owner.organization?
    end

    memoize def org_member_profile?
      organization? &&
        repository.is_org_member_profile_repository?
    end

    def readme_path
      organization? ? "/profile/README.md" : "README.md"
    end

    def possesive_name
      organization? ? "the organization's" : "your"
    end

    def add_readme_param
      if !organization?
        "readme"
      elsif org_member_profile?
        "org_member_profile_readme"
      else
        "org_profile_readme"
      end
    end

    def profile_path
      organization? ? org_root_path(repository.owner) : user_path(current_user)
    end

    def render?
      return false unless user.present?
      viewable_user_profile_repo? || (organization? && (viewable_org_profile_repo? || viewable_org_member_profile_repo?))
    end

    private

    def viewable_user_profile_repo?
      repository.user_configuration_repository? && repository.owner == user
    end

    def viewable_org_profile_repo?
      repository.is_org_profile_repository? &&
      repository.adminable_by?(user)
    end

    def viewable_org_member_profile_repo?
      repository.is_org_member_profile_repository? &&
      repository.adminable_by?(user)
    end
  end
end
