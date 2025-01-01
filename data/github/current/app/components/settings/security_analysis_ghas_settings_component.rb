# typed: true
# frozen_string_literal: true

module Settings
  class SecurityAnalysisGhasSettingsComponent < ApplicationComponent
    include SecurityAnalysisSettingsHelper

    attr_reader :private_repo_count, :public_repo_count, :repo_count, :blocked_settings

    def initialize(owner:, public_repo_count:, repo_count:, cursor:, custom_patterns_query: "", blocked_settings: nil)
      @owner = owner
      @private_repo_count = repo_count - public_repo_count
      @public_repo_count = public_repo_count
      @repo_count = repo_count
      @cursor = cursor
      @custom_patterns_query = custom_patterns_query

      @blocked_settings = blocked_settings || BlockedSettings.new(owner)

      if @blocked_settings.any?
        GitHub.dogstats.increment(
          "settings.security_features.enablement.blocking",
          tags: @blocked_settings.blockers.map { |b| "blocked_by:#{b}" } + [location_settings_tag]
        )
      end
    end

    private

    # variance in the blocking-enablement-warning tag based on if org or business
    def location_settings_tag
      @owner.is_a?(Business) ? "location:business_settings" : "location:org_settings"
    end

    memoize def security_configs_warning_banner_helper
      SecurityProductsEnablement::BusinessWarningHelper.new(@owner)
    end
  end
end
