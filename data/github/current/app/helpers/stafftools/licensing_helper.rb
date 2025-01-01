# typed: true
# frozen_string_literal: true

module Stafftools
  module LicensingHelper
    extend T::Helpers

    include GitHub::Memoizer
    include StafftoolsHelper

    sig { params(business: Business).returns(String) }
    def kusto_link_for_licensing_report(business)
      date_format = "%Y-%m-%d"
      range_end = (Time.current + 1.day).strftime(date_format)
      range_start = (Time.current - 30.days).strftime(date_format)

      raw_query =
        <<~HEREDOC
          // Licensing report for #{business.slug}
          // Note the max retention period for this data is 90 days in Kusto.
          //
          // Proxima:
          // Only the last day value is available in Proxima.
          // Replace the cluster name in the URL with
          // an appropriate value from https://github.com/github/data/blob/master/docs/proxima-data-warehouse.md.
          // Use the "local_warehouse" database and change the table name to "business_license_usages_daily".
          github_mysql1_business_license_usages
          | where business_id == #{business.id}
          | extend snapshot_date=column_ifexists("snapshot_date", now())
          | order by snapshot_date desc
          | project
            ["Date"]=format_datetime(snapshot_date, "yyyy-MM-dd"),
            ["Consumed GHE licenses"]=consumed_enterprise_licenses,
            ["Consumed VSS licenses"]=consumed_volume_licenses
        HEREDOC

      query = URI.encode_www_form_component(raw_query)

      "https://dataexplorer.azure.com/clusters/gh-analytics.eastus/databases/snapshots_all?query=#{query}"
    end

    sig { params(business: Business, current_user: T.nilable(::User)).returns(String) }
    def stafftools_ghes_license_audit_log_path(business, current_user)
      if GitHub.driftwood_ade_queries_enabled?
        query = <<~KQL
          webevents
          | where business_id == #{business.id}
          | where action startswith 'ghes_license.'
        KQL
      else
        query = "business_id:#{business.id} action:ghes_license.*"
      end

      Rails.application.routes.url_helpers.stafftools_audit_log_path(query: query)
    end

    sig { params(email: String, current_user: T.nilable(::User)).returns(String) }
    def stafftools_bundled_license_assignment_for_email_audit_log_path(email, current_user)
      if GitHub.driftwood_ade_queries_enabled?
        query = <<~KQL
          webevents
          | where action startswith "bundled_license_assignment." and data.email == "#{email}"
        KQL
      else
        query = "action:bundled_license_assignment.* data.email:#{email}"
      end

      Rails.application.routes.url_helpers.stafftools_audit_log_path(query: query)
    end

    sig { params(business: Business, current_user: T.nilable(::User)).returns(String) }
    def stafftools_business_plan_change_audit_log_path(business, current_user)
      if GitHub.driftwood_ade_queries_enabled?
        query = <<~KQL
          webevents
          | where business_id == #{business.id} and action == "account.plan_change" and toint(data.seats) != toint(data.old_seats)
        KQL
      else
        query = "business_id:#{business.id} action:account.plan_change"
      end

      Rails.application.routes.url_helpers.stafftools_audit_log_path(query: query)
    end

    sig { params(business: Business, current_user: T.nilable(::User)).returns(String) }
    def stafftools_licensing_model_changes_audit_log_path(business, current_user)
      if GitHub.driftwood_ade_queries_enabled?
        query = <<~KQL
          webevents
          | where business_id == #{business.id} and (action == "business.change_licensing_model" or action startswith "licensing_model_transition")
        KQL
      else
        query = "business_id:#{business.id} action:business.change_licensing_model action:licensing_model_transition.create"
      end

      Rails.application.routes.url_helpers.stafftools_audit_log_path(query: query)
    end

    sig { params(business: Business, current_user: T.nilable(::User)).returns(String) }
    def stafftools_enterprise_agreements_audit_log_path(business, current_user)
      if GitHub.driftwood_ade_queries_enabled?
        query = <<~KQL
          webevents
          | where business_id == #{business.id} and action startswith "business.enterprise_agreement"
        KQL
      else
        query = "business_id:#{business.id} action:business.enterprise_agreement_create action:business.enterprise_agreement_update action:business.enterprise_agreement_destroy"
      end

      Rails.application.routes.url_helpers.stafftools_audit_log_path(query: query)
    end
  end
end
