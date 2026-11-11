# typed: true
# frozen_string_literal: true

require "react_payload"

module CopilotInsights
  # Shared React payload class for all Copilot Insights controller contexts:
  # business, org, stafftools business and stafftools user/org.
  class Payload < ReactPayload::Base
    sig do
      params(
        route_id: String,
        metrics_key: CopilotInsightsUsage::Shared::MetricsKey,
        metrics: T.untyped,
        display_flags: T::Hash[Symbol, T.untyped],
        export_files_url: String,
        copilot_license_management_link: T.nilable(String),
        slug: T.nilable(String),
        canonical_query_params: T.untyped,
        copilot_disabled: T::Boolean,
        business_id: T.nilable(Integer),
        org_name: T.nilable(String),
        org_id: T.nilable(Integer),
        ai_controls_link: T.nilable(String),
        insights_opted_in: T.nilable(T::Boolean),
        can_manage_ai_controls: T.nilable(T::Boolean),
        can_manage_copilot_licenses: T.nilable(T::Boolean),
        sidenav: T.nilable(T::Hash[Symbol, T.untyped]),
        imported_data_filename: T.nilable(String)
      ).void
    end
    def initialize(
      route_id:,
      metrics_key:,
      metrics:,
      display_flags:,
      export_files_url:,
      copilot_license_management_link:,
      slug:,
      canonical_query_params:,
      copilot_disabled:,
      business_id: nil,
      org_name: nil,
      org_id: nil,
      ai_controls_link: nil,
      insights_opted_in: nil,
      can_manage_ai_controls: nil,
      can_manage_copilot_licenses: nil,
      sidenav: nil,
      imported_data_filename: nil
    )
      @route_id = route_id
      @metrics_key = metrics_key
      @metrics = metrics
      @display_flags = display_flags
      @export_files_url = export_files_url
      @copilot_license_management_link = copilot_license_management_link
      @slug = slug
      @canonical_query_params = canonical_query_params
      @copilot_disabled = copilot_disabled
      @business_id = business_id
      @org_name = org_name
      @org_id = org_id
      @ai_controls_link = ai_controls_link
      @insights_opted_in = insights_opted_in
      @can_manage_ai_controls = can_manage_ai_controls
      @can_manage_copilot_licenses = can_manage_copilot_licenses
      @sidenav = sidenav
      @imported_data_filename = imported_data_filename
    end

    sig { override.returns(String) }
    def route_id
      @route_id
    end

    sig { override.returns(T.untyped) }
    def payload
      result = {
        exportFilesUrl: @export_files_url,
        displayBlankslate: @display_flags.fetch(:blankslate, false),
        copilotDisabled: @copilot_disabled,
        displayError: @display_flags.fetch(:error, false),
        slug: @slug,
        canonicalQueryParams: @canonical_query_params,
        copilotLicenseManagementLink: @copilot_license_management_link,
      }

      # Org-specific fields
      result[:sidenav] = @sidenav unless @sidenav.nil?
      result[:org] = @org_name unless @org_name.nil?
      result[:orgId] = @org_id unless @org_id.nil?
      result[:canManageCopilotLicenses] = @can_manage_copilot_licenses unless @can_manage_copilot_licenses.nil?

      # Business-specific field
      result[:businessId] = @business_id unless @business_id.nil?

      # Customer facing only fields / non Stafftools
      result[:aiControlsLink] = @ai_controls_link unless @ai_controls_link.nil?
      result[:insightsOptedIn] = @insights_opted_in unless @insights_opted_in.nil?
      result[:canManageAiControls] = @can_manage_ai_controls unless @can_manage_ai_controls.nil?
      result[:importedDataFilename] = @imported_data_filename unless @imported_data_filename.nil?

      # Display flags
      result[:displayNoMatchingResults] = @display_flags[:no_matching_results] if @display_flags.key?(:no_matching_results)
      result[:displayUsageDisclaimer] = @display_flags[:usage_disclaimer] if @display_flags.key?(:usage_disclaimer)
      result[:displayCodeGenerationDisclaimer] = @display_flags[:code_generation_disclaimer] if @display_flags.key?(:code_generation_disclaimer)

      result[@metrics_key.serialize] = @metrics

      result
    end
  end
end
