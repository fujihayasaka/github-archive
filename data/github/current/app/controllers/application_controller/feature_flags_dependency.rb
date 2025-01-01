# typed: true
# frozen_string_literal: true

module ApplicationController::FeatureFlagsDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  included do
    # Global helpers for general use
    T.bind(self, T.class_of(ApplicationController))
    helper_method :feature_enabled_globally_or_for_current_user_or_entity?
    helper_method :user_feature_enabled?
    helper_method :user_or_global_feature_enabled?
    helper_method :user_or_global_preview_enabled?
    helper_method :repository_feature_enabled?
    helper_method :current_user_feature_enabled?

    # Feature-specific helpers below
    helper_method :discover_repos_dashboard_enabled?
    helper_method :abilities_team_enabled?
    helper_method :oauth_registered_callback_urls_enabled?
    helper_method :force_render_raw?
    helper_method :instance_audit_log_enabled?
    helper_method :desktop_survey_hashed_id
    helper_method :feature_preview_enabled?
    helper_method :flipper_session
    helper_method :wikis_visible_by_default?
    helper_method :audit_log_git_event_export_enabled?
    helper_method :can_enable_lfs_in_archives?
    helper_method :custom_search_commands_enabled?
  end

  # Public: check if a feature is enabled for the current user, globally
  # enabled or enabled for the provided organization
  #
  # `org` is optional, and `this_organization` will be checked as a fallback if
  # no `org` is passed in
  #
  # Returns a boolean
  def feature_enabled_globally_or_for_current_user_or_entity?(feature_name, entity)
    local_current_entity = current_entity(entity)
    return FeatureFlag.vexi.enabled_or_raise?(feature_name, current_user) unless local_current_entity.present? # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

    FeatureFlag.vexi.enabled_or_raise?(feature_name, local_current_entity, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  # Note: this method prefers the entity you pass in and falls back to
  # `this_organization` or `this_business` if they are defined.
  private def current_entity(entity)
    entity || (defined?(this_organization) && T.unsafe(self).this_organization) || (defined?(this_business) && T.unsafe(self).this_business)
  end

  # Public: Check if the specified feature flag is turned on for the currently authenticated user.
  # Memoizes checks to improve performance of repeated calls.
  #
  # feature_name - Symbol feature flag name, corresponding with the name from https://devportal.githubapp.com/feature-flags
  #
  # Returns a Boolean where `false` indicates either that the viewer isn't authenticated
  # or that the feature is disabled for the authenticated viewer.
  def user_feature_enabled?(feature_name)
    return false unless logged_in?

    @memoized_features ||= {}
    return @memoized_features[feature_name] if @memoized_features.key?(feature_name)
    @memoized_features[feature_name] = FeatureFlag.vexi.enabled_or_raise?(feature_name, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  # Public: Check if the specified feature flag is turned on for the currently authenticated user,
  # or fully enabled when the viewer is not logged in. Memoizes checks to improve
  # performance of repeated calls.
  #
  # feature_name - Symbol feature flag name, corresponding with the name from https://devportal.githubapp.com/feature-flags
  #
  # Returns a Boolean.
  def user_or_global_feature_enabled?(feature_name)
    @memoized_user_or_global_features ||= {}
    return @memoized_user_or_global_features[feature_name] if @memoized_user_or_global_features.key?(feature_name)
    @memoized_user_or_global_features[feature_name] = FeatureFlag.vexi.enabled_or_raise?(feature_name, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  def repository_feature_enabled?(feature_name)
    return false unless current_repository.present?

    current_repository.feature_flag_enabled_or_raise?(feature_name) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
  end

  def user_or_global_preview_enabled?(preview_name)
    @memoized_user_or_global_previews ||= {}
    return @memoized_user_or_global_previews[preview_name] if @memoized_user_or_global_previews.key?(preview_name)
    @memoized_user_or_global_previews[preview_name] = feature_preview_enabled_globally_or_for_current_user?(preview_name)
  end

  # DEPRECATED: Use `user_feature_enabled? instead`
  def current_user_feature_enabled?(sym)
    return false unless logged_in?

    FeatureFlag.vexi.enabled_or_raise?(sym, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  # Feature-specific methods below

  # define before_action restriction method for audit_log_export feature
  def audit_log_export_required
    render_404 unless logged_in? && GitHub.audit_log_export_enabled?
  end
  private :audit_log_export_required

  def audit_log_git_event_export_required
    render_404 unless audit_log_git_event_export_enabled?
  end
  private :audit_log_git_event_export_required

  def organization_members_export_required
    render_404 unless logged_in? && GitHub.organization_members_export_enabled?
  end
  private :organization_members_export_required

  # Public: Enable new 'Discover repositories' tab on the dashboard
  # See https://github.com/github/github/issues/76414
  def discover_repos_dashboard_enabled?
    !GitHub.enterprise?
  end

  def discover_repos_dashboard_required
    unless discover_repos_dashboard_enabled?
      if request.xhr? || pjax?
        head :not_found
      else
        render_404
      end
    end
  end

  def abilities_team_enabled?
    logged_in? && current_user.abilities_team_enabled?
  end

  # define controller method and helper method for `#oauth_registered_callback_urls_enabled?` user feature flag
  def oauth_registered_callback_urls_enabled?
    logged_in? && current_user.oauth_registered_callback_urls_enabled?
  end

  # Repository feature flag-related methods

  # Force raw/image rendering on a blob.  Needed for now because Git LFS objects
  # look like text files.
  def force_render_raw?
    current_repository ? current_repository.git_lfs_enabled? : false
  end

  def instance_audit_log_enabled?
    GitHub.instance_audit_log_enabled? && logged_in? && current_user.site_admin?
  end

  def desktop_survey_hashed_id
    @desktop_survey_hashed_id ||= current_user_crc32(unique_string: "In app desktop survey")
  end

  def wikis_visible_by_default?
    FeatureFlag.vexi.enabled?(:wikis_visible_by_default, default: false)
  end

  # Halts the request unless the Marketplace feature is enabled for the current request.
  #
  # This is intended for use as a `before` filter.
  #
  # Returns nothing.
  def marketplace_required
    render_404 unless GitHub.marketplace_enabled?
  end

  # Halts the request unless GitHub Models is enabled for the current request.
  #
  # This is intended for use as a `before` filter.
  #
  # Returns nothing.
  def github_models_required
    render_404 unless GitHub.models_enabled?
  end

  # Halts the request unless Copilot is enabled for the current request.
  #
  # This is intended for use as a `before` filter.
  #
  # Returns nothing.
  def copilot_required
    render_404 unless GitHub.copilot_enabled?
  end

  def sponsors_required
    render_404 unless GitHub.sponsors_enabled?
  end

  def feature_preview_enabled?
    return @feature_preview_enabled if defined?(@feature_preview_enabled)

    @feature_preview_enabled = !GitHub.enterprise?
  end

  def custom_search_commands_enabled?
    return @custom_search_commands_enabled if defined?(@custom_search_commands_enabled)
    @custom_search_commands_enabled = FeatureFlag.vexi.enabled_or_raise?(:custom_search_commands, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  # Public: Can the user enable Git LFS blobs in archives?
  #
  # Returns a Boolean.
  def can_enable_lfs_in_archives?
    return @can_enable_lfs_in_archives if defined?(@can_enable_lfs_in_archives)
    @can_enable_lfs_in_archives = current_repository&.can_enable_lfs_in_archives?
  end

  def add_client_feature_flag(flag_names, entity: current_user, &check)
    @client_feature_flags ||= {}
    flag_names.each do |flag_name|
      next unless flag_name.present? && flag_name.is_a?(String) || flag_name.is_a?(Symbol)
      if flag_name.is_a?(String)
        flag_name = flag_name.to_sym
      end
      if block_given?
        result = check.call(flag_name, entity)
        @client_feature_flags[flag_name] = result
      else
        result = feature_enabled_globally_or_for_current_user_or_entity?(flag_name, entity)
        @client_feature_flags[flag_name] = result
      end
    end
    @client_feature_flags
  end

  sig { returns T.nilable(T::Hash[T.any(String, Symbol), T::Boolean]) }
  attr_reader :client_feature_flags

  private

  def flipper_session_id
    session[FlipperSession.session_key] ||= FlipperSession.generate_id
  end

  def flipper_session
    @flipper_session ||= FlipperSession.new(flipper_session_id)
  end

  # Internal: Calculate crc32 for the current_user or a unique user id from the
  # _octo cookie for logged_out requests.
  #
  # unique_string - String additional random variable so that different popups
  #                 can be run at the same time. See
  #                 http://watchout4snakes.com/wo4snakes/Random/RandomSentence
  #                 for generating random sentences that work well for this
  #                 value.
  #
  # Returns an Integer or nil if user could not be uniquely identified.
  def current_user_crc32(unique_string:)
    id = if logged_in?
      current_user.id.to_s
    elsif cookies[:_octo] =~ /^[^.]+\.[^.]+\.\d+\.\d+$/
      # Turn "GH1.2-3.XYZ.DEF" into "XYZ.DEF"
      cookies[:_octo].split(".")[2..3].join(".")
    end

    return nil unless id

    Zlib.crc32("#{id}#{unique_string}")
  end

  def audit_log_git_event_export_enabled?
    logged_in? && GitHub.audit_log_export_enabled?
  end

  def feature_preview_enabled_globally_or_for_current_user?(preview_name)
    FeatureFlag.vexi.enabled_or_raise?(preview_name) || (logged_in? && current_user.feature_preview_enabled?(preview_name)) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end
end
