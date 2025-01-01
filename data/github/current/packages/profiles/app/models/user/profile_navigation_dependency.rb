# typed: false
# frozen_string_literal: true

module User::ProfileNavigationDependency
  NAVIGATION_REPO_NAME = ".github"
  DASHBOARD_FILE_NAME = "__dashboard.md"

  # Public: Whether or not the user has a profile readme,
  #         regardless of visiblity
  #
  # Returns a boolean
  def has_profile_navigation?
    return false unless has_navigation_repository?
    navigation_repository.has_readme?
  end

  # Public: The user's profile readme if one exists,
  #         regardless of visiblity
  #
  # Returns a TreeEntry or nil
  def profile_navigation
    async_profile_dashboard.sync
  end

  def async_profile_dashboard
    async_navigation_repository.then do |repo|
      next if repo.nil?
      repo.async_preferred_dashboard
    end
  end

  # Public: Whether or not the user is in the correct state
  #         to display a profile readme
  #
  # Returns a boolean
  def eligible_to_display_profile_navigation?
    async_eligible_to_display_profile_navigation?.sync
  end

  def async_eligible_to_display_profile_navigation?
    return Promise.resolve(false) if spammy?
    return Promise.resolve(false) if FeatureFlag.vexi.enabled?(:hide_customizable_dashboard_sidebar, self, default: false)
    return Promise.resolve(true) if FeatureFlag.vexi.enabled?(:customizable_dashboard_sidebar, self, default: false)

    # feature flag not enabled.
    Promise.resolve(false)
  end

  # Public: Whether or not the the users's profile readme
  #         is currently visible on their profile
  #
  # Returns a boolean
  def profile_navigation_visible?
    async_profile_dashboardigation_visible?.sync
  end

  def async_profile_dashboardigation_visible?
    Promise.all([
      async_eligible_to_display_profile_navigation?,
      async_navigation_repository.then,
      async_profile_dashboard
    ]).then do |is_eligible, repo, dashboard|
      next false unless repo.present?
      next false unless is_eligible

      # As of now, it's necessary to check both disabled? methods.
      # See https://github.com/github/github/pull/148922/files#r452507975
      # for details
      next false if repo.disabled?
      next false if repo.access.disabled?

      next false unless dashboard
      dashboard.data.present?
    end
  end

  def navigation_repository
    async_navigation_repository.sync
  end

  def async_navigation_repository
    return Promise.resolve(nil) unless user?
    @navigation_repo_promise ||= Promise.resolve(repositories.active.find_by_name(NAVIGATION_REPO_NAME))
  end

  def has_navigation_repository?
    navigation_repository.present?
  end
end
