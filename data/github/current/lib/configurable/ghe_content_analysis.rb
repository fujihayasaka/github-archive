# typed: true
# frozen_string_literal: true

# Whether vulnerability alerts are enabled on GHE
# (on GHE instances that are properly connected to dotcom)
module Configurable
  module GheContentAnalysis
    extend T::Helpers

    requires_ancestor { Configurable }

    ANALYSIS_KEY = "ghe_content_analysis"
    NOTIFICATIONS_KEY = "ghe_content_analysis_notifications"

    def enable_ghe_content_analysis(actor)
      return if ghe_content_analysis_enabled?
      config.enable(ANALYSIS_KEY, actor)
      GitHubConnectIndexAllReposJob.perform_later
    end

    def disable_ghe_content_analysis(actor)
      return unless ghe_content_analysis_enabled?
      config.disable(ANALYSIS_KEY, actor)
    end

    def ghe_content_analysis_enabled?
      config.enabled?(ANALYSIS_KEY)
    end

    def enable_ghe_content_analysis_notifications(actor)
      config.enable(NOTIFICATIONS_KEY, actor)
    end

    def disable_ghe_content_analysis_notifications(actor)
      config.disable(NOTIFICATIONS_KEY, actor)
    end

    def ghe_content_analysis_notifications_enabled?
      config.enabled?(NOTIFICATIONS_KEY)
    end
  end
end
