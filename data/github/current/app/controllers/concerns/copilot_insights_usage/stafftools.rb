# typed: true
# frozen_string_literal: true

require "react_payload"

module CopilotInsightsUsage
  module Stafftools
    extend T::Helpers
    extend ActiveSupport::Concern

    include ::CopilotInsightsUsage::Shared

    requires_ancestor { StafftoolsController }

    def ensure_usage_dashboard_entity_supported
      return if this_user.organization?

      render_404
    end

    private

    sig { params(spark: T::Boolean).returns(T.untyped) }
    def fetch_stafftools_dashboard_results(spark:)
      cus = cus_dashboard_enabled?(this_user)
      fetch_copilot_dashboard_results(organization: this_user, days: days, spark: spark, cus: cus)
    end

    sig do
      params(
        route_id: String,
        metrics_key: Shared::MetricsKey,
        export_files_url: String,
      ).returns(CopilotInsights::Payload)
    end
    def build_stafftools_copilot_insights_payload(route_id:, metrics_key:, export_files_url:)
      result = fetch_stafftools_dashboard_results(spark: true)
      metrics = extract_copilot_metrics(metrics_key, result)
      display_flags = result.display_flags

      CopilotInsights::Payload.new(
        route_id: route_id,
        metrics_key: metrics_key,
        metrics: metrics,
        copilot_license_management_link: stafftools_user_path(this_user),
        export_files_url: export_files_url,
        display_flags: {
          blankslate: display_flags.fetch(:blankslate, false),
          error: display_flags.fetch(:error, false),
          no_matching_results: display_flags.fetch(:no_matching_results, false),
        },
        copilot_disabled: !::Copilot::Organization.new(this_user).copilot_enabled?,
        slug: this_user.display_login,
        canonical_query_params: @canonical_params,
      )
    end
  end
end
