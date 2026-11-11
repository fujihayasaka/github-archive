# typed: true
# frozen_string_literal: true

class CopilotInsightsUsage::ReportExport
  include GitHub::Memoizer

  sig do
    params(
      enterprise: T.nilable(::Business),
      organization: T.nilable(::Organization),
      tenant_id: String,
      client_id: String,
      client_secret: String,
      storage_account_name: String,
      container_name: T.nilable(String),
      date: Date,
      client: T.nilable(::Azure::Storage::Blob::BlobService),
      use_spark_etl_path: T.nilable(T::Boolean)
    ).void
  end
  def initialize(
    enterprise: nil,
    organization: nil,
    tenant_id: GitHub.copilot_usage_reports_spn_tenant_id,
    client_id: GitHub.copilot_usage_reports_spn_client_id,
    client_secret: GitHub.copilot_usage_reports_spn_client_secret,
    storage_account_name: GitHub.copilot_usage_reports_storage_account_name,
    container_name: nil,
    date: Date.current - 1.day,
    client: nil,
    use_spark_etl_path: nil
  )
    # Validate that exactly one of enterprise or organization is provided
    if enterprise.nil? && organization.nil?
      raise ArgumentError, "Either enterprise or organization must be provided"
    elsif enterprise && organization
      raise ArgumentError, "Cannot provide both enterprise and organization"
    end

    @enterprise = T.let(enterprise, T.nilable(::Business))
    @organization = T.let(organization, T.nilable(::Organization))
    @tenant_id = tenant_id
    @client_id = client_id
    @client_secret = client_secret
    @storage_account_name = storage_account_name
    @use_spark_etl_path = T.let(use_spark_etl_path, T.nilable(T::Boolean))
    @config = Copilot::Metrics::Azure::Storage::Config.new(
      name: "copilot_metrics_report_export",
      tenant_id: tenant_id,
      client_id: client_id,
      client_secret: client_secret,
      storage_account_name: storage_account_name
    )
    @container_name = T.let(
      container_name || (organization ? "organization-users-28-day-report" : "enterprise-users-28-day"),
      String
    )
    @prefix = build_prefix(
      date: date,
      target_id: T.must(organization&.id || enterprise&.id)
    )

    @client = client
  end

  sig { returns(T::Array[Azure::Storage::Blob::Blob]) }
  def list
    GitHub.dogstats.distribution_time("copilot_insights_usage.report_export.list_blobs") do
      client.list_blobs(container_name, prefix: prefix)
    end
  end

  sig { returns(T::Array[{ name: String, url: String }]) }
  def urls
    list.map do |blob|
      filename = File.basename(blob.name)
      original_extension = File.extname(blob.name)

      if original_extension == ".json"
        filename = "#{File.basename(blob.name, ".*")}.ndjson"
        update_blob_properties(blob.name, "application/x-ndjson", filename)
      end

      # Refresh client-side blob with updated properties
      blob = client.get_blob_properties(container_name, blob.name)

      {
        name: filename,
        url: generate_sas_url_for_blob(
          blob.name,
          expires_in: CopilotInsights::Constants::DIRECT_SAS_TOKEN_EXPIRY,
          content_type: blob.properties[:content_type] || "application/octet-stream"
        )
      }
    end
  end

  sig { params(blob_name: String, expires_in: ActiveSupport::Duration, content_type: String).returns(String) }
  def generate_sas_url_for_blob(blob_name, expires_in:, content_type:)
    sas_generator.generate_sas_url(
      file_name: blob_name,
      expires_in: expires_in,
      content_type: content_type
    )
  end

  sig { params(blob_name: String, expires_in: ActiveSupport::Duration, content_type: String, afd_endpoint: String).returns(String) }
  def generate_afd_sas_url_for_blob(blob_name, expires_in:, content_type:, afd_endpoint:)
    sas_generator.generate_afd_sas_url(
      file_name: blob_name,
      expires_in: expires_in,
      content_type: content_type,
      afd_endpoint: afd_endpoint
    )
  end

  sig { params(blob_name: String, content_type: String, filename: String).void }
  def update_blob_properties(blob_name, content_type, filename)
    content_disposition = ["attachment; filename=", filename].join
    opts = {
      content_type: content_type,
      content_disposition: content_disposition
    }
    client.set_blob_properties(container_name, blob_name, options = opts)
  end

  sig { returns(String) }
  attr_reader :prefix

  private

  sig do
    params(
      date: Date,
      target_id: Integer
    ).returns(String)
  end
  def build_prefix(date:, target_id:)
    color_path = if FeatureFlag.vexi.enabled?(:copilot_insights_usage_report_green_prefix, default: false)
      "green"
    else
      "blue"
    end

    target = @organization || @enterprise

    spark_flag_enabled = if target
      FeatureFlag.vexi.enabled?(:copilot_metrics_use_spark_data, target, default: false)
    else
      FeatureFlag.vexi.enabled?(:copilot_metrics_use_spark_data, default: false)
    end

    # If use_spark_etl_path is explicitly set, use that value; otherwise fall back to existing logic
    use_spark_etl_path = if @use_spark_etl_path.nil?
      GitHub.multi_tenant_enterprise? || spark_flag_enabled
    else
      @use_spark_etl_path
    end

    # Use Proxima/Spark ETL path format when in multi-tenant environment, or when dotcom opts in.
    if use_spark_etl_path
      "etl_id=#{color_path}/day_partition=#{date}/entity_id_partition=#{target_id}/"
    else
      "#{color_path}/v0/#{date}/#{target_id}/"
    end
  end

  sig { returns(CopilotInsightsUsage::Azure::SharedAccessSignatureUrlGenerator) }
  memoize def sas_generator
    CopilotInsightsUsage::Azure::SharedAccessSignatureUrlGenerator.new(
      storage_config: @config,
      blob_container: container_name,
    )
  end

  sig { returns(::Azure::Storage::Blob::BlobService) }
  memoize def client
    return @client if @client
    azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_environment
    token_provider_settings = GitHub::Azure::ActiveDirectoryServiceSettings.get_settings(azure_environment)
    token_provider_settings.token_audience = "https://storage.azure.com/"
    token_provider = GitHub::Azure::ApplicationTokenProvider.new(
      @tenant_id,
      @client_id,
      @client_secret,
      token_provider_settings
    )
    token_provider.get_authentication_header
    access_token = token_provider.token
    token_credential = ::Azure::Storage::Common::Core::TokenCredential.new access_token
    token_signer = ::Azure::Storage::Common::Core::Auth::TokenSigner.new token_credential
    ::Azure::Storage::Blob::BlobService.create({
      storage_account_name: storage_account_name,
      signer: token_signer
    })
  end

  sig { returns(String) }
  attr_reader :storage_account_name

  sig { returns(String) }
  attr_reader :container_name
end
