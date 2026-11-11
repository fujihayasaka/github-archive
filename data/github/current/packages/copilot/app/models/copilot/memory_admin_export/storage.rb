# typed: strict
# frozen_string_literal: true

require "addressable/uri"
require "azure/core/http/http_error"
require "azure/storage/blob"
require "azure/storage/common"
require "azure/storage/common/client_options_error"
require "time"

class Copilot::MemoryAdminExport
  class Storage
    AZURE_STORAGE_TOKEN_AUDIENCE = T.let("https://storage.azure.com/", String)
    CONTAINER_NAME = T.let("ghec-admin-reports-users-exports", String)
    AZURE_OPERATION_TIMEOUT = T.let(60, Integer)

    class Error < StandardError; end

    class BlobDescriptor < T::Struct
      const :name, String
      const :last_modified, T.nilable(Time)
    end

    class BlobPage < T::Struct
      const :blob_descriptors, T::Array[BlobDescriptor]
      const :continuation_token, T.nilable(String)
    end

    sig { params(client: T.nilable(::Azure::Storage::Blob::BlobService)).void }
    def initialize(client: nil)
      @client = T.let(client, T.nilable(::Azure::Storage::Blob::BlobService))
      @azure_blob_client = T.let(nil, T.nilable(::Azure::Storage::Blob::BlobService))
      @azure_token_signer = T.let(nil, T.nilable(::Azure::Storage::Common::Core::Auth::TokenSigner))
    end

    sig { params(filename: String, block_id: String, contents: String).void }
    def stage_block!(filename:, block_id:, contents:)
      ensure_safe_filename!(filename)

      azure_errors do
        azure_blob_client.put_blob_block(
          CONTAINER_NAME,
          filename,
          block_id,
          contents,
          timeout: AZURE_OPERATION_TIMEOUT,
        )
      end
    end

    sig { params(filename: String, block_ids: T::Array[String]).void }
    def commit_blocks!(filename:, block_ids:)
      ensure_safe_filename!(filename)

      blocks = T.let(block_ids.map { |block_id| [block_id] }, T::Array[T::Array[String]])
      azure_errors do
        azure_blob_client.commit_blob_blocks(CONTAINER_NAME, filename, blocks, timeout: AZURE_OPERATION_TIMEOUT)
      end
    end

    sig { params(filename: String).returns(T::Boolean) }
    def exists?(filename)
      ensure_safe_filename!(filename)

      azure_not_found_as_false do
        azure_blob_client.get_blob_properties(CONTAINER_NAME, filename, timeout: AZURE_OPERATION_TIMEOUT)
      end
    end

    sig do
      params(
        filename: String,
        expires_in: ActiveSupport::Duration,
        content_type: String,
        content_disposition: String,
        cache_control: String,
      ).returns(String)
    end
    def download_url(filename:, expires_in:, content_type:, content_disposition:, cache_control:)
      ensure_safe_filename!(filename)

      azure_errors do
        storage_path = File.join(CONTAINER_NAME, filename)
        expiry = Time.now.utc + expires_in.to_i
        sas_token = azure_storage_signer(expires_in: expires_in).generate_service_sas_token(storage_path, {
          service: "b",
          resource: "b",
          protocol: "https",
          permissions: "r",
          expiry: expiry.to_s,
          content_disposition: content_disposition,
          content_type: content_type,
          cache_control: cache_control,
        })
        uri = Addressable::URI.parse(azure_blob_client.client.storage_blob_host)
        uri.path = storage_path
        uri.query = sas_token
        uri.to_s
      end
    end

    sig { params(prefix: String, marker: T.nilable(String), max_results: T.nilable(Integer)).returns(BlobPage) }
    def list_blobs(prefix:, marker: nil, max_results: nil)
      ensure_safe_prefix!(prefix)

      options = T.let({ prefix: prefix }, T::Hash[Symbol, T.any(String, Integer)])
      options[:marker] = marker if marker
      options[:max_results] = max_results if max_results
      options[:timeout] = AZURE_OPERATION_TIMEOUT

      azure_errors do
        result = azure_blob_client.list_blobs(CONTAINER_NAME, options)
        blob_descriptors = T.let([], T::Array[BlobDescriptor])
        T.unsafe(result).each do |blob|
          blob_descriptors << blob_descriptor(blob)
        end

        BlobPage.new(
          blob_descriptors: blob_descriptors,
          continuation_token: continuation_token(result),
        )
      end
    end

    sig { params(filename: String).returns(T::Boolean) }
    def delete_blob(filename)
      ensure_safe_filename!(filename)

      azure_not_found_as_false do
        azure_blob_client.delete_blob(CONTAINER_NAME, filename, timeout: AZURE_OPERATION_TIMEOUT)
      end
    end

    private

    sig { params(filename: String).void }
    def ensure_safe_filename!(filename)
      prefix = Copilot::MemoryAdminExport.storage_prefix
      unless safe_prefix?(prefix) && filename.start_with?(prefix) && filename != prefix
        raise ArgumentError, "unsafe Copilot Memory admin export storage filename"
      end
    end

    sig { params(prefix: String).void }
    def ensure_safe_prefix!(prefix)
      raise ArgumentError, "unsafe Copilot Memory admin export storage prefix" unless safe_prefix?(prefix)
    end

    sig { params(prefix: String).returns(T::Boolean) }
    def safe_prefix?(prefix)
      env_prefix = GitHub.filename_prefix_for_env
      return false if env_prefix.nil?
      return false if env_prefix.empty?

      prefix == "#{env_prefix}/#{Copilot::MemoryAdminExport::STORAGE_PREFIX}/"
    end

    sig do
      type_parameters(:Result)
        .params(block: T.proc.returns(T.type_parameter(:Result)))
        .returns(T.type_parameter(:Result))
    end
    def azure_errors(&block)
      yield
    rescue ::Azure::Core::Http::HTTPError => error
      raise storage_error(error)
    rescue ::Azure::Storage::Common::InvalidOptionsError => error
      raise storage_error(error, "Azure configuration invalid")
    rescue ::Faraday::Error => error
      raise storage_error(error, "Azure storage connection error")
    end

    sig { params(block: T.proc.void).returns(T::Boolean) }
    def azure_not_found_as_false(&block)
      yield
      true
    rescue ::Azure::Core::Http::HTTPError => error
      return false if azure_http_status_code(error) == 404

      raise storage_error(error)
    rescue ::Azure::Storage::Common::InvalidOptionsError => error
      raise storage_error(error, "Azure configuration invalid")
    rescue ::Faraday::Error => error
      raise storage_error(error, "Azure storage connection error")
    end

    sig { params(error: StandardError, prefix: T.nilable(String)).returns(Error) }
    def storage_error(error, prefix = nil)
      message = prefix ? "#{prefix}: #{error.message}" : error.message
      Error.new(message)
    end

    sig { params(error: ::Azure::Core::Http::HTTPError).returns(T.nilable(Integer)) }
    def azure_http_status_code(error)
      return T.unsafe(error).status_code.to_i if error.respond_to?(:status_code)

      nil
    end

    sig { returns(::Azure::Storage::Blob::BlobService) }
    def azure_blob_client
      client = @client
      return client if client

      azure_blob_client = @azure_blob_client
      return azure_blob_client if azure_blob_client

      azure_blob_client = ::Azure::Storage::Blob::BlobService.create(
        storage_account_name: GitHub.enterprise_accounts_storage_azure_account_name,
        signer: azure_token_signer,
      )
      @azure_blob_client = azure_blob_client
      azure_blob_client
    end

    sig { returns(::Azure::Storage::Common::Core::Auth::TokenSigner) }
    def azure_token_signer
      signer = @azure_token_signer
      return signer if signer

      azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_environment
      token_provider_settings = GitHub::Azure::ActiveDirectoryServiceSettings.get_settings(azure_environment)
      token_provider_settings.token_audience = AZURE_STORAGE_TOKEN_AUDIENCE

      token_provider = GitHub::Azure::ApplicationTokenProvider.new(
        GitHub.enterprise_accounts_storage_azure_spn_tenant_id,
        GitHub.enterprise_accounts_storage_azure_spn_client_id,
        GitHub.enterprise_accounts_storage_azure_spn_client_secret,
        token_provider_settings,
      )
      token_provider.get_authentication_header
      access_token = token_provider.token
      token_credential = ::Azure::Storage::Common::Core::TokenCredential.new(access_token)
      signer = ::Azure::Storage::Common::Core::Auth::TokenSigner.new(token_credential)
      @azure_token_signer = signer
      signer
    end

    sig { params(expires_in: ActiveSupport::Duration).returns(::Azure::Storage::Common::Core::Auth::SharedAccessSignature) }
    def azure_storage_signer(expires_in:)
      start_time = Time.now.utc
      expiry = start_time + expires_in.to_i
      user_delegation_key = azure_blob_client.get_user_delegation_key(start_time, expiry)
      ::Azure::Storage::Common::Core::Auth::SharedAccessSignature.new(
        azure_blob_client.client.storage_account_name,
        "",
        user_delegation_key,
      )
    end

    sig { params(blob: Object).returns(BlobDescriptor) }
    def blob_descriptor(blob)
      BlobDescriptor.new(
        name: T.cast(T.unsafe(blob).name, String),
        last_modified: blob_last_modified(blob),
      )
    end

    sig { params(result: Object).returns(T.nilable(String)) }
    def continuation_token(result)
      return unless T.unsafe(result).respond_to?(:continuation_token)

      token = T.unsafe(result).continuation_token
      token.to_s if token.present?
    end

    sig { params(blob: Object).returns(T.nilable(Time)) }
    def blob_last_modified(blob)
      properties = T.unsafe(blob).respond_to?(:properties) ? T.unsafe(blob).properties : {}
      properties = {} unless properties.respond_to?(:[])
      value = properties[:last_modified] || properties["last_modified"]
      value ||= T.unsafe(blob).last_modified if T.unsafe(blob).respond_to?(:last_modified)
      return value.utc if value.respond_to?(:utc)
      return Time.parse(value).utc if value

      nil
    rescue ArgumentError
      nil
    end
  end
end
