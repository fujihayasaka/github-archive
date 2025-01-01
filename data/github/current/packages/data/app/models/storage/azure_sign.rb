# typed: true
# frozen_string_literal: true

require "azure/storage/blob"
require "azure/core"

module Storage

  class AzureSign
    # Blob clients and User Delegation Keys are cached to be reused by further
    # requests. We will create new instances of both of them for each different
    # @uploadable.abs_storage_account_name. Requests to the same `@uploadable.abs_storage_account_name`
    # will have the chance to reuse the cached values.

    # This flag is used to enable the use of the secondary endpoint for read-only operations. When enabled
    # for a specific storage account, the download URL will be generated using the secondary endpoint
    FEATURE_FLAG_USE_READONLY_SECDONDARY_ENDPOINT = "uploadable_type_abs_use_readonly_secondary_endpoint"

    BASE_URL_DOMAIN = "blob.core.windows.net"

    # Current implementation does not prevent miss stampede side effects, so when the cache
    # would return either a miss or an expired value, multiple instances of blob_clients/udks
    # could be created simultaneously, and the last would win. This shouldn't be an issue in
    # environments that are not using threads as a concurrency model, but otherwise we will
    # wasting some resources. But in any case current implementation, despite being suboptimal
    # for this scenarios, prevents from having any data race.
    MINIMUM_UDK_TTL = 60 * 60
    DEFAULT_EXPIRATION_TIME = 5.minutes
    TOKEN_AUDIENCE = "https://storage.azure.com/"
    UDK_REFRESH_TIMEOUT = 3
    UDK_FETCH_JITTER = 60
    UDK_FETCH_BUFFER = 3.minutes
    SAS_PERMISSIONS = { read: "r", write: "w", delete: "d" }

    @blob_clients_mutex = Mutex.new
    @blob_clients = {}
    @udks_mutex = Mutex.new
    @udks = {}

    def initialize(uploadable)
      @uploadable = uploadable
    end

    def self.add_blob_client(abs_storage_account_name, blob_client, expiration)
      @blob_clients_mutex.synchronize do
        @blob_clients[abs_storage_account_name] = [blob_client, expiration]
      end
    end

    def self.get_blob_client(abs_storage_account_name)
      @blob_clients_mutex.synchronize do
        @blob_clients[abs_storage_account_name]
      end
    end

    def self.add_udk(abs_storage_account_name, udk)
      @udks_mutex.synchronize do
        @udks[abs_storage_account_name] = udk
      end
    end

    def self.get_udk(abs_storage_account_name)
      @udks_mutex.synchronize do
        @udks[abs_storage_account_name]
      end
    end

    def self.abs_url(abs_storage_account_name)
      "https://#{abs_storage_account_name}.#{BASE_URL_DOMAIN}"
    end

    def self.primary_and_secondary_abs_urls(abs_storage_account_name)
      primary_url = abs_url(abs_storage_account_name)
      secondary_url = abs_url(secondary_storage_account_name(abs_storage_account_name))
      [primary_url, secondary_url]
    end

    def self.secondary_storage_account_name(abs_storage_account_name)
      "#{abs_storage_account_name}-secondary"
    end

    def base_url
      "#{self.class.abs_url(storage_account_name_with_primary_or_secondary)}/#{@uploadable.storage_abs_container}/#{@uploadable.storage_abs_key(@uploadable.storage_policy)}"
    end

    def generate_signed_blob_url(permissions = :read, expiration = nil)
      key, expiry = user_delegation_key(expiration)

      # Generate the signed blob URL
      sas_generator = Azure::Storage::Common::Core::Auth::SharedAccessSignature.new(
        @uploadable.abs_storage_account_name,
        "",
        key
      )

      # Build SAS token options with response override parameters if available
      sas_options = {
        service: "b",           # blob
        resource: "b",          # blob
        protocol: "https",
        permissions: SAS_PERMISSIONS[permissions],
        expiry: expiry.to_s
      }

      # Add content disposition if the uploadable supports it
      if @uploadable.respond_to?(:storage_azure_content_disposition) && @uploadable.storage_azure_content_disposition != nil
        sas_options[:content_disposition] = @uploadable.storage_azure_content_disposition
      end

      # Add content type if the uploadable supports it
      if @uploadable.respond_to?(:storage_download_content_type) && @uploadable.storage_download_content_type != nil
        sas_options[:content_type] = @uploadable.storage_download_content_type
      end

      sas_token = sas_generator.generate_service_sas_token(
        "#{@uploadable.storage_abs_container}/#{@uploadable.storage_abs_key(@uploadable.storage_policy)}",
        sas_options
      )

      "#{base_url}?#{sas_token}"
    end

    def add_jwt_token_to_query(query, path)
      query.merge(jwt: generate_jwt_token_for(path))
    end

    def add_content_disposition_to_query(query)
      query.merge("response-content-disposition":  @uploadable.storage_azure_content_disposition)
    end

    def add_content_type_to_query(query)
      query.merge("response-content-type": @uploadable.storage_download_content_type)
    end

    private

    def generate_jwt_token_for(path)
      timestamp = Time.now.to_i

      payload = {
        iss: "github.com",
        aud: "#{@uploadable.fastly_jwt_audience}",
        key: @uploadable.fastly_dictionary_key_name,
        exp: DEFAULT_EXPIRATION_TIME.from_now.to_i,
        nbf: timestamp,
        path: "#{path}"
      }
      JWT.encode(payload, @uploadable.fastly_dictionary_key_value, "HS256", { typ: "JWT" })
    end

    def user_delegation_key(expiration = nil)
      # For ad-hoc expiration parameters we just create a new user delegation
      # that will be used solely for this request, otherwise use the cached value if
      # possible.
      if FeatureFlag.vexi.enabled?(:extend_direct_download_udk_key_start, default: false)
        return [fetch_user_delegation_key(Time.now.utc - 60.minutes, Time.now.utc + expiration), Time.now.utc + expiration] unless expiration.nil?
      else
        return [fetch_user_delegation_key(Time.now.utc, Time.now.utc + expiration), Time.now.utc + expiration] unless expiration.nil?
      end

      # We can use an existing UDK regardless if it was fetched from the primary or secondary, since
      # UDKs are interchangeable between primary and secondary endpoints.
      udk = self.class.get_udk(@uploadable.abs_storage_account_name)
      if !udk.nil? && ((Time.parse(udk.signed_expiry) - Time.now.utc) > (@uploadable.storage_download_expiration.to_i) + UDK_FETCH_BUFFER.to_i)
        return [udk, Time.parse(udk.signed_expiry)]
      end

      # Either we did not have yet an UDK or it was gonna expire before the requested expiration
      sas_expiration = Time.now.utc + [MINIMUM_UDK_TTL, @uploadable.storage_download_expiration.to_i * 2].max + SecureRandom.rand(UDK_FETCH_JITTER)
      udk = fetch_user_delegation_key(Time.now.utc, sas_expiration)
      self.class.add_udk(@uploadable.abs_storage_account_name, udk)
      [udk, sas_expiration]
    end

    def fetch_user_delegation_key(start_time, expiry_time)
      timer_start = GitHub::Dogstats.monotonic_time
      begin
        delegation_key = Timeout.timeout(UDK_REFRESH_TIMEOUT) { blob_client.get_user_delegation_key(start_time, expiry_time) }
        result = "ok"
      rescue => e
        GitHub.logger.error("error generating new user delegation key, storage account #{@uploadable.abs_storage_account_name}", e)
        result = "error"
        raise
      ensure
        GitHub.dogstats.distribution(
          "azure_sign.user_delegation_key.time",
          GitHub::Dogstats.duration(timer_start),
          tags: { "account_name" => @uploadable.abs_storage_account_name, "result" => result, "geoendpoint" => (failover_to_secondary? ? "secondary" : "primary") }
        )
      end
      delegation_key
    end

    def failover_to_secondary?
      return true if FeatureFlag.vexi.enabled?(FEATURE_FLAG_USE_READONLY_SECDONDARY_ENDPOINT, "AzureAccountName:#{@uploadable.abs_storage_account_name}", default: false)
      false
    end

    def storage_account_name_with_primary_or_secondary
      if failover_to_secondary?
        self.class.secondary_storage_account_name(@uploadable.abs_storage_account_name)
      else
        @uploadable.abs_storage_account_name
      end
    end

    def blob_client
      # will return either the primary or secondary blob client, depending on the feature flag resolution
      # UDKs fetched from one or the other are interchangeable, and can be used for signing SAS URLs for both
      # primary and secondary endpoints.
      blob_client, token_expires_on = self.class.get_blob_client(storage_account_name_with_primary_or_secondary)
      if !blob_client.nil? && ((token_expires_on.to_i - Time.now.utc.to_i) > (@uploadable.storage_download_expiration.to_i) + UDK_FETCH_BUFFER.to_i)
        return blob_client
      end

      azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_environment
      token_provider_settings = GitHub::Azure::ActiveDirectoryServiceSettings.get_settings(azure_environment)
      token_provider_settings.token_audience = TOKEN_AUDIENCE
      token_provider = GitHub::Azure::ApplicationTokenProvider.new(
        @uploadable.abs_spn_tenant_id,
        @uploadable.abs_spn_client_id,
        @uploadable.abs_spn_client_secret,
        token_provider_settings
      )
      token_credential = TokenCredential.new(token_provider, @uploadable.abs_storage_account_name)
      token_signer = ::Azure::Storage::Common::Core::Auth::TokenSigner.new token_credential
      blob_client = ::Azure::Storage::Blob::BlobService.create({
        storage_account_name: storage_account_name_with_primary_or_secondary,
        signer: token_signer
      })
      self.class.add_blob_client(storage_account_name_with_primary_or_secondary, blob_client, token_credential.token_expires_on)
      blob_client
    end

    class TokenCredential < ::Azure::Storage::Common::Core::TokenCredential

      MINIMUM_TOKEN_TTL = 1.minute
      attr_accessor :token_expires_on

      def initialize(token_provider, abs_storage_account_name)
        super(nil)
        token_expires_on = nil
        @token = nil
        @token_provider = token_provider
        @abs_storage_account_name = abs_storage_account_name
        @mutex = Mutex.new
        token
      end

      def token
        timer_start = GitHub::Dogstats.monotonic_time
        @mutex.synchronize do
          if !@token.nil? && (self.token_expires_on > Time.now + MINIMUM_TOKEN_TTL)
            return @token
          end
          begin
            @token_provider.get_authentication_header
            @token = @token_provider.token
            self.token_expires_on = @token_provider.token_expires_on
            result = "ok"
          rescue => e
            GitHub.logger.error("error generating new token for blob client, storage account #{@abs_storage_account_name}", e)
            result = "error"
            raise
          ensure
            GitHub.dogstats.distribution(
              "uploadable_type.memoryalphaspnpolicy.token_generation.time",
              GitHub::Dogstats.duration(timer_start),
              tags: { "account_name" => @abs_storage_account_name, "result" => result }
            )
          end
          @token
        end
      end
    end
  end
end
