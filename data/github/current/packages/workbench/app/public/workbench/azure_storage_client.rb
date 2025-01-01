# typed: strict
# frozen_string_literal: true

module Workbench
  class AzureStorageClient
    extend T::Helpers

    AZURE_STORAGE_TOKEN_AUDIENCE = "https://storage.azure.com/"
    MS_VERSION = "2021-12-02"

    sig { void }
    def initialize
      # Initialize with service principal authentication for workbench
      azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_environment
      token_provider_settings = GitHub::Azure::ActiveDirectoryServiceSettings.get_settings(azure_environment)
      token_provider_settings.token_audience = AZURE_STORAGE_TOKEN_AUDIENCE

      @token_provider = T.let(GitHub::Azure::ApplicationTokenProvider.new(
        GitHub.copilot_workbench_spn_tenant_id,
        GitHub.copilot_workbench_spn_client_id,
        GitHub.copilot_workbench_spn_client_secret,
        token_provider_settings
      ), T.nilable(GitHub::Azure::ApplicationTokenProvider))
    end

    sig { params(method: Symbol, uri: String, params: T::Hash[T.untyped, T.untyped], headers: T::Hash[T.untyped, T.untyped], body: T.untyped).returns(T.untyped) }
    def send_request(method:, uri:, params: {}, headers: {}, body: nil)
      begin
        response = connection.send(method, uri) do |request| # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
          request.options.timeout = 20
          request.body = body
          request.headers["Accept"] = "application/json"
          # Add authorization header
          if @token_provider
            request.headers["Authorization"] = @token_provider.get_authentication_header
          end
          request.params.merge!(params)
          request.headers.merge!(headers)
        end
      rescue Faraday::Error => e
        GitHub.logger.error("failed to send request", { "exception" => e, "code.namespace" => self.class.name, "code.function" => __method__ })
        raise e
      end

      response
    end

    sig { params(container_name: String, permissions: String, expiry_minutes: Integer, storage_account_name: String, blob_name: T.nilable(String)).returns(String) }
    def generate_user_delegation_sas_uri(container_name:, permissions:, expiry_minutes:, storage_account_name:, blob_name: nil)
      now = Time.now.utc
      expiration_time = now + expiry_minutes.minutes

      # Get the user delegation key which we sign the SAS with
      user_delegation_key = get_user_delegation_key(expiration_time: expiration_time, storage_account_name: storage_account_name)

      # Generate the SAS token which includes the signature
      sas_token = generate_user_delegation_sas_token(
        storage_account_name: storage_account_name,
        container_name: container_name,
        blob_name: blob_name,
        start_time: now.iso8601,
        expiry_duration: expiration_time.iso8601,
        user_delegation_key: user_delegation_key,
        permissions: permissions
      )

      # Append SAS token to the URL and you have your expiring URL
      resource_path = blob_name ? "#{container_name}/#{blob_name}" : container_name
      "https://#{storage_account_name}.blob.core.windows.net/#{resource_path}?#{sas_token}"
    end

    sig { params(storage_account_name: String).returns(::Azure::Storage::Blob::BlobService) }
    def get_client(storage_account_name:)
      azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_environment
      token_provider_settings = GitHub::Azure::ActiveDirectoryServiceSettings.get_settings(azure_environment)
      token_provider_settings.token_audience = AZURE_STORAGE_TOKEN_AUDIENCE
      token_provider = GitHub::Azure::ApplicationTokenProvider.new(
        GitHub.copilot_workbench_spn_tenant_id,
        GitHub.copilot_workbench_spn_client_id,
        GitHub.copilot_workbench_spn_client_secret,
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

    private

    sig { returns(Faraday::Connection) }
    def connection
      @connection ||= T.let(GitHub::FaradayClient::Internal.new do |builder|
        builder.use ::GitHub::FaradayMiddleware::RaiseError
        builder.request :retry,
          methods: [:delete, :get, :head, :merge, :patch, :post, :put],
          retry_statuses: [408, 429, *500...600],
          exceptions: [Errno::ETIMEDOUT, "Timeout::Error", Faraday::TimeoutError, Faraday::RetriableResponse, Faraday::ConnectionFailed],
          interval: 0.05,
          interval_randomness: 0.5,
          backoff_factor: 2
        builder.request :json
        builder.response :json, content_type: /\bjson\z/, parser_options: { symbolize_names: true }
        builder.adapter Faraday.default_adapter
      end, T.nilable(GitHub::FaradayClient::Internal))
    end

    sig { params(expiration_time: Time, storage_account_name: String).returns(T::Hash[String, String]) }
    def get_user_delegation_key(expiration_time:, storage_account_name:)
      now = Time.now.utc

      request_body = %&<?xml version="1.0" encoding="utf-8"?><KeyInfo><Start>#{now.iso8601}</Start><Expiry>#{expiration_time.iso8601}</Expiry></KeyInfo>&

      response = send_request(
        method: :post,
        uri: "https://#{storage_account_name}.blob.core.windows.net/?restype=service&comp=userdelegationkey",
        headers: {
          "x-ms-version": MS_VERSION
        },
        body: request_body
      )

      Hash.from_xml(response.body)["UserDelegationKey"]
    rescue Net::HTTPError, REXML::ParseException, NoMethodError => e
      GitHub.logger.error("failed getting delegation key", { "exception" => e, "code.namespace" => self.class.name, "code.function" => __method__, "storage" => storage_account_name })
      raise
    end

    sig do
      params(
        storage_account_name: String,
        container_name: String,
        blob_name: T.nilable(String),
        start_time: String,
        expiry_duration: String,
        user_delegation_key: T::Hash[String, String],
        permissions: String
      ).returns(String)
    end
    def generate_user_delegation_sas_token(storage_account_name:, container_name:, blob_name:, start_time:, expiry_duration:, user_delegation_key:, permissions:)
      sas_fields = {
        signed_permissions: {
          value: permissions,
          key_name: "sp",
        },
        signed_start: {
          value: start_time,
          key_name: "st",
        },
        signed_expiry: {
          value: expiry_duration,
          key_name: "se",
        },
        canonicalized_resource: {
          value: blob_name ? "/blob/#{storage_account_name}/#{container_name}/#{blob_name}" : "/blob/#{storage_account_name}/#{container_name}",
          key_name: "",
        },
        signed_key_object_id: {
          value: user_delegation_key["SignedOid"],
          key_name: "skoid",
        },
        signed_key_tenant_id: {
          value: user_delegation_key["SignedTid"],
          key_name: "sktid",
        },
        signed_key_start: {
          value: user_delegation_key["SignedStart"],
          key_name: "skt",
        },
        signed_key_expiry: {
          value: user_delegation_key["SignedExpiry"],
          key_name: "ske",
        },
        signed_key_service: {
          value: user_delegation_key["SignedService"],
          key_name: "sks",
        },
        signed_key_version: {
          value: user_delegation_key["SignedVersion"],
          key_name: "skv",
        },
        signed_authorized_user_object_id: {
          value: "",
          key_name: "saoid",
        },
        signed_unauthorized_user_object_id: {
          value: "",
          key_name: "suoid",
        },
        signed_correlation_id: {
          value: "",
          key_name: "scid",
        },
        signed_ip: {
          value: "",
          key_name: "sip",
        },
        signed_protocol: {
          value: "https",
          key_name: "spr",
        },
        signed_version: {
          value: "2021-12-02",
          key_name: "sv",
        },
        signed_resource: {
          value: blob_name ? "b" : "c", # Blob or Container
          key_name: "sr",
        },
        signed_snapshot_time: {
          value: "",
          key_name: "",
        },
        signed_encryption_scope: {
          value: "",
          key_name: "ses",
        },
        # Response header override fields - required even if empty
        cache_control: {
          value: "",
          key_name: "rscc",
        },
        content_disposition: {
          value: "",
          key_name: "rscd",
        },
        content_encoding: {
          value: "",
          key_name: "rsce",
        },
        content_language: {
          value: "",
          key_name: "rscl",
        },
        content_type: {
          value: "",
          key_name: "rsct",
        },
      }

      # Iterate over the keys to create a string to sign, this must be ordered and written exactly how Azure expects
      # See https://learn.microsoft.com/en-us/rest/api/storageservices/create-user-delegation-sas#version-2020-12-06-and-later
      # All fields must be included in the exact order, even if empty
      string_to_sign_parts = [
        sas_fields[:signed_permissions][:value],
        sas_fields[:signed_start][:value],
        sas_fields[:signed_expiry][:value],
        sas_fields[:canonicalized_resource][:value],
        sas_fields[:signed_key_object_id][:value],
        sas_fields[:signed_key_tenant_id][:value],
        sas_fields[:signed_key_start][:value],
        sas_fields[:signed_key_expiry][:value],
        sas_fields[:signed_key_service][:value],
        sas_fields[:signed_key_version][:value],
        sas_fields[:signed_authorized_user_object_id][:value],
        sas_fields[:signed_unauthorized_user_object_id][:value],
        sas_fields[:signed_correlation_id][:value],
        sas_fields[:signed_ip][:value],
        sas_fields[:signed_protocol][:value],
        sas_fields[:signed_version][:value],
        sas_fields[:signed_resource][:value],
        sas_fields[:signed_snapshot_time][:value],
        sas_fields[:signed_encryption_scope][:value],
        sas_fields[:cache_control][:value],
        sas_fields[:content_disposition][:value],
        sas_fields[:content_encoding][:value],
        sas_fields[:content_language][:value],
        sas_fields[:content_type][:value]
      ]
      string_to_sign = string_to_sign_parts.join("\n")

      # Generate a signature using the user delegation key we requested
      sig = generate_signature(account_key: T.must(user_delegation_key["Value"]), string_to_sign: string_to_sign)

      # Create the actual token which must be based on the string we signed
      params_to_include = %w[st skt sks skv ske skoid sp sktid se spr sv sr]
      query_string = sas_fields.filter_map do |_, query_param|
        [query_param[:key_name], query_param[:value]] if params_to_include.include?(query_param[:key_name])
      end.to_h

      query_string["sig"] = sig
      URI.encode_www_form(query_string)
    rescue OpenSSL::OpenSSLError, ArgumentError => e
      GitHub.logger.error("failed generating user delegation sas token", { "exception" => e, "code.namespace" => self.class.name, "code.function" => __method__, "storage" => storage_account_name })
      raise
    end

    sig { params(account_key: String, string_to_sign: String).returns(String) }
    def generate_signature(account_key:, string_to_sign:)
      Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", Base64.decode64(account_key), string_to_sign))
    end
  end
end
