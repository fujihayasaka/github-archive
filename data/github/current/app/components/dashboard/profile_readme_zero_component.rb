# typed: true
# frozen_string_literal: true

module Dashboard
  class ProfileReadmeZeroComponent < ApplicationComponent
    include HydroHelper

    NOTICE_NAME = "dashboard_profile_readme_banner"
    HYDRO_EVENT_CONTEXT = :PROFILE_README_BANNER

    private

    def render?
      return false if GitHub.enterprise?
      return false unless logged_in?
      return false if dismissed?

      !current_user.has_profile_readme?
    end

    def dismissed?
      current_user.dismissed_notice?(NOTICE_NAME)
    end

    # Public: Separated lines of the quick start profile readme template
    #         to display as an example.
    #
    # Returns an Array[String].
    memoize def template_lines
      current_user.profile_readme_quick_start_template(
        include_comment: false
      ).lines
    end

    def continue_button_data_attributes
      hydro_click_tracking_attributes(
        "dashboard.click",
        event_context: HYDRO_EVENT_CONTEXT,
        dashboard_context: "user",
        dashboard_version: DashboardAnalyticsHelper::DASHBOARD_VERSION,
        target: :CREATE_PROFILE_README,
      )
    end
  end
end
