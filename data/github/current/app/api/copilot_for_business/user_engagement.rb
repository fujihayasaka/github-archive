# typed: strict
# frozen_string_literal: true

class Api::CopilotForBusiness::UserEngagement < Api::App
  USER_ENGAGEMENT_SCHEMA_VERSION = 3
  REPORTS_BLOB_CONTAINER = "reports"

  EARLY_ACCESS_DOCS_URL = "https://docs.github.com/en/enterprise-cloud@latest/early-access/copilot/user-level-feature-engagement-metrics-api"

  # Enterprise User Engagement endpoint
  get "/enterprises/:enterprise_id/copilot/user-engagement", operation_id: "copilot/copilot-user-engagement-for-enterprise" do
    enterprise = find_enterprise!

    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") if !GitHub.copilot_metrics_available? ||
      !enterprise.feature_enabled?(:copilot_enterprise_user_engagement_api)

    ensure_policy_enabled!(enterprise)

    control_access :copilot_enterprise_user_engagement,
      resource: enterprise,
      allow_user_via_granular_actor: false,
      allow_integrations: false,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_FORBID_MESSAGE

    user_engagement = user_engagement_for_entity!(enterprise)
    response = generate_response!(user_engagement)
    deliver_raw(response)
  end

  private

  # TODO: we need to use a separate policy at some point: https://github.com/github/copilot-metrics/issues/290
  # This also should support multiple entity types when we add support for orgs/teams/ets
  sig { params(entity: Business).returns(NilClass) }
  def ensure_policy_enabled!(entity)
    copilot_entity = Copilot::Business.new(entity)
    enabled = copilot_entity.telemetry_aggregation_enabled?

    unless enabled
      deliver_error!(422,
        documentation_url: EARLY_ACCESS_DOCS_URL,
        message: "Your enterprise has disabled Copilot Metrics API access. Enable it in GitHub settings to access this endpoint."
      )
    end
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def date_params
    {
      since_date: params[:since].present? ? parse_time!(params[:since], documentation_url: EARLY_ACCESS_DOCS_URL).to_date : nil,
      until_date: params[:until].present? ? parse_time!(params[:until], documentation_url: EARLY_ACCESS_DOCS_URL).to_date : nil
    }
  end

  sig { params(entity: T.anything).returns(T::Array[Copilot::UsageMetric]) }
  def user_engagement_for_entity!(entity)
    dates = date_params
    since_date = dates[:since_date]
    until_date = dates[:until_date]

    if since_date && since_date < 28.days.ago
      deliver_error!(422, documentation_url: EARLY_ACCESS_DOCS_URL, message: "Value of since parameter cannot be prior to 28 days ago.")
    end

    if since_date && until_date && until_date < since_date
      deliver_error!(422, documentation_url: EARLY_ACCESS_DOCS_URL, message: "Until date cannot be prior to since date.")
    end

    case entity
    when Business
      # TODO: maybe create a separate Class to represent this? similar to Copilot::Metrics::CopilotMetrics
      if since_date || until_date
        Copilot::UsageMetric.for_business(entity, USER_ENGAGEMENT_SCHEMA_VERSION)
          .between_dates(since_date, until_date)
          .order("date ASC").to_ary
      else
        Copilot::UsageMetric.for_business(entity, USER_ENGAGEMENT_SCHEMA_VERSION)
          .last_28_days.order("date ASC").to_ary
      end
    else
      []
    end
  end

  # We're responding in a format of [ {date, blob_uri} ]
  # Metadata schema is `{"date": "2025-01-29", "blob_uri": "https://copilotengagement.blob.core.windows.net/reports/12345/2025-01-29.json"}'`
  sig { params(usage_metrics: T::Array[Copilot::UsageMetric]).returns(T::Array[T::Hash[Symbol, String]]) }
  def generate_response!(usage_metrics)
    # if the report exists we need to sign it to actually grant access
    sas_generator = Copilot::Metrics::Azure::SharedAccessSignatureUrlGenerator.new(
      storage_config: Copilot::Metrics::Azure::Storage.copilot_user_engagement_config,
      blob_container: REPORTS_BLOB_CONTAINER,
    )

    usage_metrics.map do |metric|
      blob_uri = metric.metadata["blob_uri"]
      response = { date: metric.metadata["date"] }

      # Only include blob_uri in the response if it exists in metadata
      unless blob_uri.nil? || blob_uri.empty?
        file_name = T.must(URI(blob_uri).path).delete_prefix("/reports/")
        signed_uri = sas_generator.generate_sas_url(
          file_name: file_name,
          expires_in: 1.hour,
          content_type: "json"
        )
        response[:blob_uri] = signed_uri
      end

      response
    end
  end
end
