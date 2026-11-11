# typed: true
# frozen_string_literal: true

module Hooks
  class OauthApplicationPolicyView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :hook

    delegate :repo_hook?, :org_hook?, :oauth_application, to: :hook

    def policymaker
      if org_hook?
        organization
      elsif repo_hook?
        repository.policymaker
      end
    end

    def repository
      hook.installation_target if repo_hook?
    end

    def organization
      if org_hook?
        hook.installation_target
      elsif repo_hook? && hook.installation_target.organization
        hook.installation_target.organization
      end
    end

    def app_link_or_name
      if organization.adminable_by?(current_user) && organization
        helpers.link_to oauth_application.name, urls.org_application_approval_path(organization, oauth_application)
      else
        helpers.content_tag :strong, oauth_application.name # rubocop:disable Rails/ViewModelHTML
      end
    end

    def violates_policy?
      return false unless oauth_application

      if repo_hook?
        repo_hook_violates_policy?
      elsif org_hook?
        org_hook_violates_policy?
      else
        false
      end
    end

    def blocked_by_org?
      return false unless org_hook?

      !organization.allows_oauth_application?(oauth_application)
    end

    def violated_org_repos
      return [] unless org_hook?

      @violated_repos ||= begin
        # Hooks on private repos always go out
        Repository.oauth_app_policy_violated_repository_scope(
          repository_scope: organization.repositories.private_scope,
          app: oauth_application,
        ).all
      end
    end

    private

    def repo_hook_violates_policy?
      # Hooks on private repos always go out
      return false unless repository.private?

      OauthApplicationPolicy::Application.new(repository, oauth_application).violated?
    end

    def org_hook_violates_policy?
      blocked_by_org? || violated_org_repos.any?
    end
  end
end
