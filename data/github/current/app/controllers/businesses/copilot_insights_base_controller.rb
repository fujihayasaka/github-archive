# typed: strict
# frozen_string_literal: true

require "react_payload"

class Businesses::CopilotInsightsBaseController < Businesses::BusinessController
  include CopilotInsightsPermissions
  include ::CopilotInsightsUsage::Params
  include Businesses::CopilotShared

  depends_on_clusters ApplicationRecord::Mysql1, ApplicationRecord::Configurations, ApplicationRecord::IamAbilities, ApplicationRecord::Copilot

  before_action :login_required
  before_action :dotcom_required
  before_action :canonicalize_query_params

  sig { returns(T.nilable(String)) }
  def self.react_bundle_name
    "copilot-insights-shared"
  end

  private

  sig do
    params(
      route_id: String,
      metrics_key: Symbol,
      display_flags: T::Hash[Symbol, T::Boolean],
      license_management_link: T.nilable(String),
      ai_controls_link: T.nilable(String),
      opted_in: T::Boolean
    ).void
  end
  def render_insights_response(route_id:, metrics_key:, display_flags: {}, license_management_link: nil, ai_controls_link: nil, opted_in: false)
    results = fetch_dashboard_results

    metrics, page_type = get_metrics_from_result(metrics_key, results)

    export_files_url = copilot_insights_export_files_enterprise_insights_path(current_business, page_type: page_type)

    copilot_insights_payload = CopilotInsightsPayload.new(
      route_id: route_id,
      metrics_key: metrics_key,
      metrics: metrics,
      display_flags: results.display_flags,
      slug: current_business&.slug,
      business_id: current_business&.id,
      export_files_url: export_files_url,
      license_management_link: license_management_link || "",
      ai_controls_link: get_ai_controls_link,
      canonical_params: @canonical_params,
      imported_data_filename: imported_data_filename,
      insights_opted_in: opted_in
    )

    respond_with_react(
      payload: copilot_insights_payload,
      title: page_title,
      page_data: {
        sidebar: :insights,
        selected_link: sidebar_link
      },
      layout: "react_business",
    )
  end

  sig { params(metrics_key: Symbol, results: T.untyped).returns([T.untyped, String]) }
  def get_metrics_from_result(metrics_key, results)
    case metrics_key
    when :usageMetrics
      [results.usage_metrics, "usage"]
    when :codeGenerationMetrics
      [results.code_generation_metrics, "code_generation"]
    else
      raise ArgumentError, "Unknown metrics key: #{metrics_key}"
    end
  end

  sig { returns(String) }
  def page_title
    raise NotImplementedError, "Child controllers must implement page_title"
  end

  sig { returns(Symbol) }
  def sidebar_link
    raise NotImplementedError, "Child controllers must implement sidebar_link"
  end

  sig { returns(T.untyped) }
  def fetch_dashboard_results
    ::CopilotInsightsUsage::DashboardService.call(business: current_business, days: days)
  end

  sig { returns(T.nilable(String)) }
  def imported_data_filename
    ::Copilot::Metrics::UsageReport::EnterpriseReportImporter.imported_data_filename
  end

  sig { returns(String) }
  def get_ai_controls_link
    if standalone_business?
      settings_copilot_enterprise_path(current_business)
    else
      copilot_enterprise_ai_controls_enterprise_path(current_business)
    end
  end

  class CopilotInsightsPayload < ReactPayload::Base
    sig do params(
      route_id: String,
      metrics_key: Symbol,
      metrics: T.untyped,
      display_flags: T::Hash[Symbol, T::Boolean],
      slug: String,
      business_id: Integer,
      export_files_url: String,
      license_management_link: T.nilable(String),
      ai_controls_link: T.nilable(String),
      canonical_params: T.untyped,
      imported_data_filename: T.nilable(String),
      insights_opted_in: T::Boolean
    ).void
    end
    def initialize(route_id:, metrics_key:, metrics:, display_flags:, slug:, business_id:,
                  export_files_url:, license_management_link:, ai_controls_link:, canonical_params:, imported_data_filename: nil, insights_opted_in: false)
      @route_id = route_id
      @metrics_key = metrics_key
      @metrics = metrics
      @display_flags = display_flags
      @slug = slug
      @business_id = business_id
      @export_files_url = export_files_url
      @license_management_link = license_management_link
      @ai_controls_link = ai_controls_link
      @canonical_params = canonical_params
      @imported_data_filename = imported_data_filename
      @insights_opted_in = insights_opted_in
    end

    sig { override.returns(String) }
    def route_id
      @route_id
    end

    sig { override.returns(T.untyped) }
    def payload
      result = {
        exportFilesUrl: @export_files_url,
        displayBlankslate: @display_flags[:blankslate],
        displayUsageDisclaimer: @display_flags[:usage_disclaimer],
        displayCodeGenerationDisclaimer: @display_flags[:code_generation_disclaimer],
        displayError: @display_flags[:error],
        slug: @slug,
        businessId: @business_id,
        canonicalQueryParams: @canonical_params,
        insightsOptedIn: @insights_opted_in
      }

      result[@metrics_key] = @metrics

      result[:copilotLicenseManagementLink] = @license_management_link
      result[:aiControlsLink] = @ai_controls_link

      # Include imported data filename for development if available
      result[:importedDataFilename] = @imported_data_filename if @imported_data_filename

      result
    end
  end
end
