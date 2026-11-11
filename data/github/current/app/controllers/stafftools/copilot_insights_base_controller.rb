# typed: true
# frozen_string_literal: true

class Stafftools::CopilotInsightsBaseController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods
  include ::CopilotInsightsUsage::Stafftools

  before_action :ensure_user_exists
  before_action :ensure_usage_dashboard_entity_supported
  before_action :canonicalize_query_params

  layout :content_layout

  def show
    respond_with_react(
      payload: build_stafftools_copilot_insights_payload(
        route_id: copilot_insights_route_id,
        metrics_key: copilot_insights_metrics_key,
        export_files_url: stafftools_user_copilot_insights_export_files_path(this_user, **export_files_params),
        spark: copilot_insights_spark?
      ),
      title: copilot_insights_title,
      layout: content_layout
    )
  end

  private

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

  # Override in Spark subclasses to return true
  sig { returns(T::Boolean) }
  def copilot_insights_spark?
    false
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def export_files_params
    copilot_insights_spark? ? { spark: true } : {}
  end
end
