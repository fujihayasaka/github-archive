# typed: true
# frozen_string_literal: true

module Prerelease
  class BadgeView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include ApplicationHelper

    attr_reader :feature_flag
    attr_reader :public_name
    attr_reader :external_feedback_url
    attr_reader :internal_feedback_url
    attr_reader :additional_classes
    attr_reader :current_repository

    # Should the prerelease badge be displayed to the current user?
    #
    # Note: The badge is not displayed if the feature is disabled, or if
    # the feature has been fully released (and thus is no-longer pre-release)
    def display_badge?
      return false unless logged_in? && current_user.prerelease_badges?
      feature_enabled? && flipper_feature && !flipper_feature.fully_enabled?
    end

    # The URL to which the current user should direct feedback.
    # This will be the internal URL for staff and the external URL for maintainers
    def feedback_url
      if current_user.maintainers_early_access?
        external_feedback_url
      elsif current_user.preview_features?
        internal_feedback_url
      end
    end

    private

    def feature_enabled?
      FeatureFlag.vexi.enabled?(feature_flag, current_user, current_repository, default: false)
    end

    def flipper_feature
      @flipper_feature ||= FlipperFeature.find_by(name: feature_flag) # rubocop:disable GitHub/FeatureManagement/NoFlipperFeatureUsage
    end
  end
end
