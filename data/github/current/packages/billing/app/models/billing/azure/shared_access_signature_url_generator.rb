# typed: strict
# frozen_string_literal: true


# Azure documentation: https://learn.microsoft.com/en-us/azure/storage/common/storage-sas-overview
# This class generates a url that grants secure access to Azure Storage Blob resources, leveraging shared access signature (SAS).
# More specifically, User delegation SAS is being used.
module Billing::Azure
  class SharedAccessSignatureUrlGenerator
    extend T::Sig
    include UrlHelper

    MS_VERSION = "2021-12-02"

    @azure_http_client = T.let(nil, T.nilable(Billing::Azure::HttpClient))

    sig { returns(String) }
    attr_accessor :blob_container

    sig { returns(Billing::Azure::Storage::Config) }
    attr_accessor :storage_config

    sig { params(storage_config: Billing::Azure::Storage::Config, blob_container: String).void }
    def initialize(storage_config:, blob_container:)
      @blob_container = blob_container
      @storage_config = storage_config
    end

    sig { params(storage_config: Billing::Azure::Storage::Config, blob_container: String, file_name: String, expires_in: ActiveSupport::Duration, content_type: String).returns(String) }
    def self.generate_sas_url(storage_config:, blob_container:, file_name:, expires_in:, content_type:)
      new(storage_config:, blob_container:).generate_sas_url(file_name:, expires_in:, content_type:)
    end

    sig { params(file_name: String, expires_in: ActiveSupport::Duration, content_type: String).returns(String) }
    def generate_sas_url(file_name:, expires_in:, content_type:)
      now = Time.now.utc
      expiration_time = now + expires_in.to_i
      storage_account_name = storage_config.storage_account_name || ""

      ## Get the user delegation key which we sign the SAS with
      user_delegation_key = get_user_delegation_key(expiration_time:, storage_account_name:)

      ## Generate the SAS token which includes the signature
      sas_token = generate_sas_token(
        storage_account_name: storage_account_name,
        container_name: blob_container,
        blob_name: file_name,
        start_time: now.iso8601,
        expiry_duration: (expiration_time).iso8601,
        user_delegation_key: user_delegation_key,
        content_type: content_type
      )

      #Append SAS token to the URL and you have your expiring URL
      "https://#{storage_account_name}.blob.core.windows.net/#{blob_container}/#{file_name}?#{sas_token}"
    end

    private

    sig do params(
      storage_account_name: String,
      container_name: String,
      blob_name: String,
      start_time: String,
      expiry_duration: String,
      user_delegation_key: T::Hash[String, String],
      content_type: String).returns(String)
    end
    def generate_sas_token(storage_account_name:, container_name:, blob_name:, start_time:, expiry_duration:, user_delegation_key:, content_type:)
      sas_fields = {
        signed_permissions: {
          value: "r", # read permission only
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
          value: "/blob/#{storage_account_name}/#{container_name}/#{blob_name}",
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
          value: "b",
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
        cache_control: {
          value: "",
          key_name: "rscc",
        },
        content_disposition: {
          value: "attachment",
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
          value: content_type,
          key_name: "rsct",
        },
      }

      ## Iterate over the keys to create a string to sign, this must be ordered and written exactly how Azure expects
      ## See https://learn.microsoft.com/en-us/rest/api/storageservices/create-user-delegation-sas#version-2020-12-06-and-later
      string_to_sign = sas_fields.map { |_, query| query[:value] }.join("\n")

      ##Generate a signature using the user delegation key we requested
      sig = generate_signature(account_key:  T.must(user_delegation_key["Value"]), string_to_sign: string_to_sign)

      ##Create the actual token which must be based on the string we signed
      params_to_include = %w[st skt sks skv ske skoid sp sktid se spr sv sr rscd rsct]
      query_string = sas_fields.filter_map do |_, query_param|
        [query_param[:key_name], query_param[:value]] if params_to_include.include?(query_param[:key_name])
      end.to_h

      query_string["sig"] = sig
      URI.encode_www_form(query_string)
    end

    sig { params(account_key: String, string_to_sign: String).returns(String) }
    def generate_signature(account_key:, string_to_sign:)
      Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", Base64.decode64(account_key), string_to_sign))
    end

    sig { params(expiration_time: Time, storage_account_name: String).returns(T::Hash[String, String]) }
    def get_user_delegation_key(expiration_time:, storage_account_name:)
      now = Time.now.utc

      request_body = %&<?xml version="1.0" encoding="utf-8"?><KeyInfo><Start>#{now.iso8601}</Start><Expiry>#{(expiration_time).iso8601}</Expiry></KeyInfo>&

      response = azure_http_client.send_request(
        method: :post,
        uri: "https://#{storage_account_name}.blob.core.windows.net/?restype=service&comp=userdelegationkey",
        headers: {
          "x-ms-version": MS_VERSION
        },
        body: request_body
      )

      Hash.from_xml(response.body)["UserDelegationKey"]
    end

    sig { returns(Billing::Azure::HttpClient) }
    def azure_http_client
      @azure_http_client ||= T.let(Billing::Azure::HttpClient.new(storage_config: storage_config), T.nilable(Billing::Azure::HttpClient))
    end
  end
end
