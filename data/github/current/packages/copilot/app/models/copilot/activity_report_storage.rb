# typed: strict
# frozen_string_literal: true

module Copilot
  class ActivityReportStorage
    include GitHub::Memoizer

    sig { returns(String) }
    attr_reader :storage_account_name

    sig { returns(String) }
    attr_reader :container_name

    sig { returns(String) }
    attr_reader :prefix

    NAME = "copilot_activity.report_storage"

    sig do
      params(
        entity_id: Integer,
        # should be :business or :organization
        entity_type: Symbol,
        tenant_id: String,
        client_id: String,
        client_secret: String,
        storage_account_name: String,
        container_name: String,
        client: T.nilable(::Azure::Storage::Blob::BlobService)
      ).void
    end
    def initialize(
      entity_id:,
      entity_type:,
      tenant_id: GitHub.copilot_user_engagement_spn_tenant_id,
      client_id: GitHub.copilot_user_engagement_spn_client_id,
      client_secret: GitHub.copilot_user_engagement_spn_client_secret,
      storage_account_name: GitHub.copilot_user_engagement_storage_account_name,
      container_name: "copilot-activity-reports",
      client: nil
    )
      @entity_id = entity_id
      @entity_type = T.let(entity_type, Symbol)
      @tenant_id = tenant_id
      @client_id = client_id
      @client_secret = client_secret
      @storage_account_name = storage_account_name
      @config = T.let(
        Copilot::Metrics::Azure::Storage::Config.new(
          name: "copilot_activity_report_storage",
          tenant_id: tenant_id,
          client_id: client_id,
          client_secret: client_secret,
          storage_account_name: storage_account_name
        ), Copilot::Metrics::Azure::Storage::Config
      )
      @container_name = T.let(container_name, String)
      @prefix = T.let("#{@entity_type}/#{entity_id}", String)
      @client = client
    end

    sig { returns(T::Array[Azure::Storage::Blob::Blob]) }
    def list
      client.list_blobs(container_name, prefix: prefix)
    end

    sig { params(blob_name: String, expires_in: ActiveSupport::Duration, content_type: String).returns(String) }
    def download_url(blob_name, expires_in:, content_type:)
      sas_generator.generate_sas_url(
        file_name: blob_name,
        expires_in: expires_in,
        content_type: content_type
      )
    end

    sig { params(filename: String, content: String).returns(GitHub::Result) }
    def store(filename:, content:)
      GitHub.logger.with_named_tags(
        "gh.copilot.entity.id" => @entity_id,
        "gh.copilot.entity.type" => @entity_type,
      ) do
        with_exception_handling do
          GitHub.logger.info("Starting activity report storage")

          result = client.create_block_blob(container_name, "#{prefix}/#{filename}", content, {
            content_type: "text/csv"
          })

          GitHub.logger.info("Activity report storage success")
          GitHub.dogstats.increment("#{NAME}.store.success", tags: ["entity:#{@entity_type}"])

          result
        end
      end
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

    sig do
      type_parameters(:V)
        .params(block: T.proc.returns(T.type_parameter(:V)))
        .returns(GitHub::Result)
    end
    def with_exception_handling(&block)
      GitHub::Result.new do
        yield
      rescue ::Azure::Core::Http::HTTPError => error
        error = Copilot::Errors::ActivityReportStorageError.new(error.message)
        Copilot::ErrorReporter.report!(error)
        GitHub.dogstats.increment("#{NAME}.errors", tags: ["type:http_error"])
        error
      end
    end
  end
end
