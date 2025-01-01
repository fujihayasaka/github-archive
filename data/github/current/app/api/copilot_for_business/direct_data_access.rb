# typed: strict
# frozen_string_literal: true

require "date"


class Api::CopilotForBusiness::DirectDataAccess < Api::App
  EARLY_ACCESS_DOCS_URL = "https://docs.github.com/en/enterprise-cloud@latest/early-access/copilot/direct-data-access"
  REPORTS_BLOB_CONTAINER = "enterprises"
  MAX_REPORTING_DATES_PER_REQUEST = 14

  get "/enterprises/:enterprise_id/copilot/direct-data", operation_id: "copilot/copilot-direct-data-access" do
    enterprise = find_enterprise!
    # check authorized (feature flag, user, enterprise, etc)
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") if !GitHub.copilot_metrics_available? ||
      !enterprise.feature_enabled?(:copilot_direct_data)

    ensure_policy_enabled!(enterprise)

    control_access  :copilot_enterprise_direct_data_access,
      resource: enterprise,
      allow_user_via_granular_actor: false,
      allow_integrations: false,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_FORBID_MESSAGE


    # reach out to kusto to get data (get date params)
    data = query_kusto!(enterprise)
    # do any data messaging required(SAS sign urls so they are usable by the client)
    response = format_response!(data)
    # return response
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

  # example response [["11468", "GitHub", "2025-03-09T00:00:00Z", "2025-03-10T00:07:27.0205992Z", ["https://copilotdirectdata.blob.core.windows.net/enterprises/v0/11468/2025-03-09/8d3992cf-2a72-4f93-947e-8c7272f422b3_1_0a0a7ef9d1b4432aa82fde4891c338a2.gz.parquet"]],
  sig { params(entity: Business).returns(::Kusto::Data::Table) }
  def query_kusto!(entity)
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
    # if both are nil, we just default to yesterday

    dda = Copilot::Metrics::Queries::DirectDataAccess.new(enterprise_id: entity.id, since_date: since_date, until_date: until_date)
    kusto_client = Copilot::Metrics::Azure::KustoClientProvider.kusto_client
    kusto_client.query("copilot", dda.get_reports).primary_result_table
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def date_params
    {
      since_date: params[:since].present? ? parse_time!(params[:since], documentation_url: EARLY_ACCESS_DOCS_URL) : nil,
      until_date: params[:until].present? ? parse_time!(params[:until], documentation_url: EARLY_ACCESS_DOCS_URL) : nil
    }
  end

  sig { params(table: ::Kusto::Data::Table).returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
  def format_response!(table)
    columns = table.columns
    target_date_index = columns.find_index { |column| column.name == "target_date" }
    uris_index = columns.find_index { |column| column.name == "uris" }
    sas_generator = Copilot::Metrics::Azure::SharedAccessSignatureUrlGenerator.new(
      storage_config: Copilot::Metrics::Azure::Storage.copilot_direct_data_access_config,
      blob_container: REPORTS_BLOB_CONTAINER,
    )

    response = []
    rows = table.rows
    # create an array of hashes with a date property and a url property
    # the date property should be a string formatted as "YYYY-MM-DD"
    # the url property should be an array of strings formatted as urls
    if rows.any?
      rows.each do |row|
        # trim date to just be YYYY-MM-DD
        date = Date.parse(row[target_date_index.to_i]).to_date.to_s
        uris = row[uris_index.to_i]
        signed_uris = []
        entry = { date: date }
        if uris.any?
          uris.each do |uri|
            # sign the uri
            file_name = T.must(URI(uri).path).delete_prefix("/#{REPORTS_BLOB_CONTAINER}/")
            signed_uri = sas_generator.generate_sas_url(
              file_name: file_name,
              expires_in: 1.hour,
              content_type: "parquet"
            )
            signed_uris << signed_uri
          end
          entry[:blob_uris] = signed_uris
        end
        response << entry
      end
    end
    response
  end
end
