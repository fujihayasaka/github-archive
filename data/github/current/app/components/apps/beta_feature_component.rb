# typed: true
# frozen_string_literal: true

module Apps
  class BetaFeatureComponent < ApplicationComponent
    renders_one :note

    BETA_FEATURES = {}

    def initialize(application:, feature_flag:)
      @application  = application
      @feature_flag = feature_flag
      @user         = @application.user
    end

    def render?
      FeatureFlag.vexi.enabled_or_raise?(global_flag, owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    end

    memoize def beta_feature_enabled?
      FeatureFlag.vexi.enabled_or_raise?(@feature_flag, @application) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    end

    def submit_value
      beta_feature_enabled? ? "Opt-out" : "Opt-in"
    end

    def title
      BETA_FEATURES[@feature_flag][:title]
    end

    def toggle_method
      beta_feature_enabled? ? :delete : :post
    end

    def toggle_path
      if @user.organization?
        settings_org_applications_beta_features_path(@user, @application)
      else
        settings_user_applications_beta_features_path(@application)
      end
    end

    def toggle_value
      beta_feature_enabled? ? "Disable" : "Enable"
    end

    private

    memoize def owner
      @application.owner
    end

    memoize def global_flag
      BETA_FEATURES[@feature_flag][:global_flag]
    end
  end
end
