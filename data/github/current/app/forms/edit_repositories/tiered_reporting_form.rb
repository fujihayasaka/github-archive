# typed: false
# frozen_string_literal: true

module EditRepositories
  class TieredReportingForm < ApplicationForm
    ALLOW_ALL_USERS = "all_users".freeze
    PRIOR_CONTRIBUTORS = "prior_contributors".freeze
    DISABLE = "disable".freeze

    form do |tiered_reporting_form|
      tiered_reporting_form.radio_button_group(name: "tiered_reporting_settings", label: "Report content setting") do |tiered_reports_group|
        tiered_reports_group.radio_button(
          value: ALLOW_ALL_USERS,
          label: "All users",
          caption: "Any user on GitHub is able to report content",
          checked: @report_content_all_users_enabled
        )

        tiered_reports_group.radio_button(
          value: PRIOR_CONTRIBUTORS,
          label: "Prior contributors and collaborators",
          caption: "Only users who have previously contributed to the repository and collaborators will be able to report content",
          checked: @report_content_prior_contributors_enabled
        )

        tiered_reports_group.radio_button(
          value: DISABLE,
          label: "Disable content reporting",
          caption: "Disable content reporting for all users",
          checked: tiered_reporting_disabled,
        )
      end

      tiered_reporting_form.submit(name: :submit, label: "Save")
    end

    def initialize(report_content_prior_contributors_enabled:, report_content_all_users_enabled:)
      @report_content_prior_contributors_enabled = report_content_prior_contributors_enabled
      @report_content_all_users_enabled = report_content_all_users_enabled
    end

    private

    def tiered_reporting_disabled
      !@report_content_prior_contributors_enabled && !@report_content_all_users_enabled
    end
  end
end
