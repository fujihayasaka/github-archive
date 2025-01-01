# typed: strict
# frozen_string_literal: true

require "date"


class Api::CopilotForBusiness::DirectDataAccess < Api::App
  EARLY_ACCESS_DOCS_URL = "https://docs.github.com/en/enterprise-cloud@latest/early-access/copilot/direct-data-access"
  REPORTS_BLOB_CONTAINER = "enterprises"
  MAX_REPORTING_DATES_PER_REQUEST = 14
  DIRECT_DATA_ACCESS_SCHEMA_VERSION = 4

  get "/enterprises/:enterprise_id/copilot/direct-data", operation_id: "copilot/copilot-direct-data-access" do
    enterprise = find_enterprise!
    # check authorized (feature flag, user, enterprise, etc)
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") if !GitHub.copilot_metrics_available? ||
      !enterprise.feature_flag_enabled_or_raise?(:copilot_direct_data) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

    ensure_policy_enabled!(enterprise)

    control_access  :copilot_enterprise_direct_data_access,
      resource: enterprise,
      allow_user_via_granular_actor: false,
      allow_integrations: false,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_FORBID_MESSAGE

    data = direct_data_access_for_entity_mysql!(enterprise)
    response = format_response_mysql!(data)

    deliver_raw(response)
  end

  private

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
      since_date: params[:since].present? ? parse_time!(params[:since], documentation_url: EARLY_ACCESS_DOCS_URL) : nil,
      until_date: params[:until].present? ? parse_time!(params[:until], documentation_url: EARLY_ACCESS_DOCS_URL) : nil
    }
  end

  # query copilot_usage_metrics for the given entity's direct data access reports
  sig { params(entity: T.anything).returns(T::Array[Copilot::UsageMetric]) }
  def direct_data_access_for_entity_mysql!(entity)
    dates = date_params
    since_date = dates[:since_date]
    until_date = dates[:until_date]

    if since_date && since_date < 365.days.ago
      deliver_error!(422, documentation_url: EARLY_ACCESS_DOCS_URL, message: "Value of since parameter cannot be prior to 365 days ago.")
    end

    if since_date && until_date && until_date < since_date
      deliver_error!(422, documentation_url: EARLY_ACCESS_DOCS_URL, message: "Until date cannot be prior to since date.")
    end

    # we limit the response to a total range of 14 days for performance reasons
    if since_date && until_date
      days_diff = (until_date.to_date - since_date.to_date).to_i
      if days_diff > MAX_REPORTING_DATES_PER_REQUEST
        deliver_error!(422, documentation_url: EARLY_ACCESS_DOCS_URL, message: "Date range cannot exceed 14 days.")
      end
    elsif since_date
      until_date = since_date + MAX_REPORTING_DATES_PER_REQUEST.days
    elsif until_date
      since_date = until_date - MAX_REPORTING_DATES_PER_REQUEST.days
    end

    case entity
    when Business
      if since_date || until_date
        Copilot::UsageMetric.for_business(entity, DIRECT_DATA_ACCESS_SCHEMA_VERSION)
          .between_dates(since_date, until_date)
          .order("date ASC").to_ary
      else
        Copilot::UsageMetric.for_business(entity, DIRECT_DATA_ACCESS_SCHEMA_VERSION)
          .last_14_days.order("date ASC").to_ary
      end
    else
      []
    end
  end

  # Sign and format the blob uris for each day's direct data access report.
  # We're responding in a format of [ {date, [blob_uris]} ]
  sig { params(usage_metrics: T::Array[Copilot::UsageMetric]).returns(T::Array[T::Hash[Symbol, String]]) }
  def format_response_mysql!(usage_metrics)
    # if the report exists we need to sign it to actually grant access
    sas_generator = Copilot::Metrics::Azure::SharedAccessSignatureUrlGenerator.new(
      storage_config: Copilot::Metrics::Azure::Storage.copilot_direct_data_access_config,
      blob_container: REPORTS_BLOB_CONTAINER,
    )

    usage_metrics.map do |metric|
      blob_uris = metric.metadata["blob_uris"]
      response = { date: metric.metadata["date"] }
      if blob_uris&.any?
        blob_uris.each do |uri|
          # sign the uri if it exists for the entity
          unless uri.nil? || uri.empty?
            file_name = T.must(URI(uri).path).delete_prefix("/#{REPORTS_BLOB_CONTAINER}/")
            signed_uri = sas_generator.generate_sas_url(
              file_name: file_name,
              expires_in: 1.hour,
              content_type: "parquet"
            )
            response[:blob_uris] ||= []
            response[:blob_uris] << signed_uri
          end
        end
      end

      response
    end
  end
end
