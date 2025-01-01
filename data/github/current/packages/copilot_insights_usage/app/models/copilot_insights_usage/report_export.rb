# typed: true
# frozen_string_literal: true

class CopilotInsightsUsage::ReportExport
  include GitHub::Memoizer

  sig do
    params(
      enterprise_id: Integer,
      tenant_id: String,
      client_id: String,
      client_secret: String,
      storage_account_name: String,
      container_name: String,
      date: Date,
      client: T.nilable(::Azure::Storage::Blob::BlobService)
    ).void
  end
  def initialize(
    enterprise_id:,
    tenant_id: GitHub.copilot_usage_reports_spn_tenant_id,
    client_id: GitHub.copilot_usage_reports_spn_client_id,
    client_secret: GitHub.copilot_usage_reports_spn_client_secret,
    storage_account_name: GitHub.copilot_usage_reports_storage_account_name,
    container_name: "enterprise-users-28-day",
    date: Date.current - 1.day,
    client: nil
  )
    @tenant_id = tenant_id
    @client_id = client_id
    @client_secret = client_secret
    @storage_account_name = storage_account_name
    @config = Copilot::Metrics::Azure::Storage::Config.new(
      name: "copilot_metrics_report_export",
      tenant_id: tenant_id,
      client_id: client_id,
      client_secret: client_secret,
      storage_account_name: storage_account_name
    )
    @container_name = T.let(container_name, String)
    prefix = T.let("#{date}/#{enterprise_id}/", String)
    if FeatureFlag.vexi.enabled?(:copilot_insights_usage_report_green_prefix, default: false)
      @prefix = "green/v0/#{prefix}"
    else
      @prefix = "blue/v0/#{prefix}"
    end

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
      {
        name: File.basename(blob.name),
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

  private

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

  sig { returns(String) }
  attr_reader :prefix
end
