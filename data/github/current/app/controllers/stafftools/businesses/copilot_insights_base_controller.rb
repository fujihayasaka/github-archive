# typed: true
# frozen_string_literal: true

require "react_payload"

module Stafftools
  module Businesses
    class CopilotInsightsBaseController < Stafftools::Businesses::BusinessBaseController
      include ::CopilotInsightsUsage::Shared
      include ::Copilot::Businesses::InsightsExport

      before_action :canonicalize_query_params

      def show
        respond_with_react_opts = {
          payload: build_copilot_insights_payload,
          title: copilot_insights_title,
          layout: "layouts/stafftools/business"
        }

        respond_with_react(**respond_with_react_opts)
      end

      def export_files # rubocop:todo GitHub/UseRestfulActions
        begin
          export_files = generate_export_files(this_business, **export_files_kwargs)
          render json: { export_files: export_files }
        rescue => e
          Failbot.report(e)
          render json: { error: "Unable to fetch export files" }, status: :internal_server_error
        end
      end

      private

      sig { returns(CopilotInsights::Payload) }
      def build_copilot_insights_payload
        metrics_key = copilot_insights_metrics_key
        result = fetch_copilot_dashboard_results(business: this_business, days: days, spark: copilot_insights_spark?)
        metrics = extract_copilot_metrics(metrics_key, result)
        display_flags = result.display_flags
        copilot_business = ::Copilot::Business.new(this_business)

        CopilotInsights::Payload.new(
          route_id: copilot_insights_route_id,
          metrics_key: metrics_key,
          metrics: metrics,
          copilot_license_management_link: stafftools_enterprise_licensing_path(this_business),
          export_files_url: copilot_insights_export_files_url,
          display_flags: {
            blankslate: display_flags.fetch(:blankslate, false),
            error: display_flags.fetch(:error, false),
          },
          copilot_disabled: !copilot_business.copilot_seat_count.positive?,
          slug: this_business&.slug,
          canonical_query_params: @canonical_params
        )
      end

      # @abstract Override in subclass to provide the React route identifier
      sig { returns(String) }
      def copilot_insights_route_id
        raise NotImplementedError, "Subclass must implement copilot_insights_route_id"
      end

      # @abstract Override in subclass to provide the metrics key
      sig { returns(CopilotInsightsUsage::Shared::MetricsKey) }
      def copilot_insights_metrics_key
        raise NotImplementedError, "Subclass must implement copilot_insights_metrics_key"
      end

      # @abstract Override in subclass to provide the page title
      sig { returns(String) }
      def copilot_insights_title
        raise NotImplementedError, "Subclass must implement copilot_insights_title"
      end

      # @abstract Override in subclass to provide the export files URL
      sig { returns(String) }
      def copilot_insights_export_files_url
        raise NotImplementedError, "Subclass must implement copilot_insights_export_files_url"
      end

      # Override in Spark subclasses to return true
      sig { returns(T::Boolean) }
      def copilot_insights_spark?
        false
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def export_files_kwargs
        copilot_insights_spark? ? { report_class: ::Copilot::Metrics::SparkUsageReport } : {}
      end

    end
  end
end
