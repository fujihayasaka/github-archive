# typed: true
# frozen_string_literal: true

module Stafftools
  module LicensingHelper
    extend T::Sig
    extend T::Helpers

    include GitHub::Memoizer
    include StafftoolsHelper

    sig { params(business: Business).returns(String) }
    def kusto_link_for_licensing_watermark_report(business)
      date_format = "%Y-%m-%d"
      range_end = (Time.current + 1.day).strftime(date_format)
      range_start = (Time.current - 30.days).strftime(date_format)

      raw_query =
        <<~HEREDOC
          // License watermark report for #{business.slug}
          // Update range_start and range_end to generate the report for a different date range.
          // Note the max retention period for this data is 90 days in Kusto. Older data is available in the data warehouse.
          let range_start = datetime(#{range_start});
          let range_end = datetime(#{range_end});
          let business_id = '#{business.id}';
          github_billing_v0_license_snapshot
          | where
              timestamp >= range_start
              and timestamp <= range_end
              and business.id == business_id
          | summarize
              EnterpriseWatermark=max(filled_enterprise_seats),
              VolumeWatermark=max(filled_volume_seats)
              by format_datetime(Date=bin(timestamp, 1d),'yyyy-MM-dd')
          | order by Date desc
        HEREDOC

      query = URI.encode_www_form_component(raw_query)

      "https://dataexplorer.azure.com/clusters/ghdwprod.eastus/databases/hydro?query=#{query}"
    end

    sig { params(business: Business, current_user: T.nilable(::User)).returns(String) }
    def stafftools_ghes_license_audit_log_path(business, current_user)
      if driftwood_ade_query?(current_user)
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
      if driftwood_ade_query?(current_user)
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
      if driftwood_ade_query?(current_user)
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
      if driftwood_ade_query?(current_user)
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
      if driftwood_ade_query?(current_user)
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
