# typed: true
# frozen_string_literal: true

module ApplicationController::CodeNavDependency
  extend T::Helpers
  requires_ancestor { ApplicationController }
  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(ApplicationController))
    helper_method :aleph_code_navigation_viewable?
    helper_method :aleph_code_navigation_available?
    helper_method :aleph_show_proxy_backend_enabled?
    helper_method :aleph_unified_code_nav_enabled?
    helper_method :aleph_cross_repo_jump_to_definition_enabled?
    helper_method :aleph_index_on_pull_request_create_enabled?
    helper_method :aleph_precise_preview_code_nav_enabled?
    helper_method :aleph_precise_development_code_nav_enabled?
    helper_method :aleph_request_index_enabled?
    helper_method :aleph_diff_request_index_enabled?
    helper_method :aleph_disable_anon_code_navigation_enabled?
  end

  def aleph_disable_anon_code_navigation_enabled?
    feature_enabled_globally_or_for_current_user?(:aleph_disable_anon_code_navigation)
  end

  def aleph_code_navigation_available?
    GitHub.aleph_code_navigation_enabled? &&
      !robot? &&
      !mobile? &&
      logged_in? &&
      current_repository &&
      current_repository.alephd_indexing_enabled?
  end

  def aleph_code_navigation_available_for_react?
    GitHub.aleph_code_navigation_enabled? && current_repository
  end

  def aleph_code_navigation_viewable?(lang)
    feature_enabled_globally_or_for_current_user?(GitHub::Aleph.convert_language_name(lang))
  end

  def aleph_unified_code_nav_enabled?
    # If the feature is enabled globally then it's trivially enabled for both
    # the current repo and the current user.
    return true if GitHub.flipper[:aleph_unified_code_nav].enabled?

    # If we're not viewing a repo, then flag off the feature as a safeguard.
    return false unless current_repository

    # Otherwise the feature must be enabled for BOTH the current user AND the
    # current repository for us to show Code Index results.
    aleph_unified_code_nav_enabled_for_repo? && aleph_unified_code_nav_enabled_for_user?
  end

  private def aleph_unified_code_nav_enabled_for_repo?
    # The feature is enabled for the current repository if any of the following
    # are true:

    # 1. The feature is enabled specifically for the repo
    return true if GitHub.flipper[:aleph_unified_code_nav].enabled?(current_repository)

    # 2. The repo's owner is an org, and the repo is enabled for the org
    current_repository.owner&.organization? &&
      GitHub.flipper[:aleph_unified_code_nav].enabled?(current_repository.owner)
  end

  private def aleph_unified_code_nav_enabled_for_user?
    # The feature is enabled for the current user if any of the following are
    # true:

    # 1. The feature is enabled specifically for the current user, and the user
    #    has opted in via Feature Preview.  (If they have opted out, that choice
    #    takes precedence.)
    if GitHub.flipper[:aleph_unified_code_nav].enabled?(current_user)
      return current_user.feature_preview_enabled?(:aleph_unified_code_nav)
    end

    # 2. The feature is NOT enabled for the current user, but IS enabled for the
    #    owner of the current (org-scoped) repository, AND the current user is a
    #    member of that organization.
    current_repository&.owner&.organization? &&
      GitHub.flipper[:aleph_unified_code_nav].enabled?(current_repository.owner) &&
      current_repository.owner.member?(current_user)
  end

  def aleph_show_proxy_backend_enabled?
    user_feature_enabled?(:aleph_show_proxy_backend)
  end

  def aleph_cross_repo_jump_to_definition_enabled?
    feature_enabled_globally_or_for_current_user?(:aleph_cross_repo_jump_to_definition)
  end

  def aleph_index_on_pull_request_create_enabled?
    user_feature_enabled?(:aleph_index_on_pull_request_create)
  end

  def aleph_precise_preview_code_nav_enabled?
    user_feature_enabled?(:aleph_precise_preview_code_nav)
  end

  def aleph_precise_development_code_nav_enabled?
    user_feature_enabled?(:aleph_precise_development_code_nav)
  end

  def aleph_request_index_enabled?
    GitHub.aleph_code_navigation_enabled? &&
      current_repository &&
      logged_in? &&
      feature_enabled_globally_or_for_current_user?(:aleph_request_index)
  end

  def aleph_diff_request_index_enabled?
    GitHub.aleph_code_navigation_enabled? &&
      current_repository &&
      logged_in? &&
      feature_enabled_globally_or_for_current_user?(:aleph_diff_request_index)
  end
end
