# typed: true
# frozen_string_literal: true

require "azure/storage/blob"
require "azure/core"

module Storage

  # This policy extends the MemoryAlphaPolicy and overrides the `download_url` method.
  # The `download_url` method generates SAS URLs that directly target the ABS account
  # using SPN credentials with access to the ABS account.
  # Use this implementation to direct traffic to the ABS account, bypassing Memory Alpha when downloading.
  # Using the `MemoryAlphaPolicy`involves an additional round trip, as it returns a redirect to the
  # ABS account.

  # By default, if the `spn_*` methods are not defined on the `@uploadable` object, it will use the
  # global SPN credentials used by MA. If you configured an ABS account which gives access to the MA
  # SPN credentials, you can use the defaults.

  class MemoryAlphaWithDirectAbsDownloadPolicy < Storage::MemoryAlphaPolicy
    # Blob clients and User Delegation Keys are cached to be reused by further
    # requests. We will create new instances of both of them for each different
    # @uploadable.abs_storage_account_name. Requests to the same `@uploadable.abs_storage_account_name`
    # will have the chance to reuse the cached values.

    # This flag is used to enable the use of the secondary endpoint for read-only operations. When enabled
    # for a specific storage account, the download URL will be generated using the secondary endpoint
    FEATURE_FLAG_USE_READONLY_SECDONDARY_ENDPOINT = "uploadable_type_abs_use_readonly_secondary_endpoint"

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

    @blob_clients_mutex = Mutex.new
    @blob_clients = {}
    @udks_mutex = Mutex.new
    @udks = {}

    def self.add_blob_client(abs_storage_account_name, blob_client)
      @blob_clients_mutex.synchronize do
        @blob_clients[abs_storage_account_name] = blob_client
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

    def base_url
      "https://#{storage_account_name_with_primary_or_secondary}.blob.core.windows.net/#{@uploadable.storage_abs_container}/#{@uploadable.storage_abs_key(self)}"
    end

    def download_url(_ = nil, expiration: nil)
      now = Time.now
      parsed = Addressable::URI.parse(base_url)
      signed_url = generate_signed_blob_url(expiration)
      query = {}

      uses_fastly = @uploadable.memory_alpha_fastly_acceleration_bucket(@actor, @repository)

      if uses_fastly
        query = add_jwt_token_to_query(query, parsed.host)
      end

      query_string = "&#{query.to_query}" unless query.empty?
      url = "#{signed_url}#{query_string}"

      cdn_url(url)
    ensure
      stats_timing(:download, start: now) if now
    end

    private

    def add_jwt_token_to_query(query, path)
      query.merge(jwt: generate_jwt_token_for(path))
    end

    def generate_jwt_token_for(path)
      timestamp = Time.now.to_i

      payload = {
        iss: "github.com",
        aud: "#{GitHub.memory_alpha_host}",
        key: @uploadable.fastly_dictionary_key_name,
        exp: DEFAULT_EXPIRATION_TIME.from_now.to_i,
        nbf: timestamp,
        path: "#{path}"
      }
      JWT.encode(payload, GitHub.private_abs_asset_cdn_key, "HS256", { typ: "JWT" })
    end

    def user_delegation_key(expiration = nil)
      # For ad-hoc expiration parameters we just create a new user delegation
      # that will be used solely for this request, otherwise use the cached value if
      # possible.
      return fetch_user_delegation_key(Time.now.utc, Time.now.utc + expiration) unless expiration.nil?

      # We can use an existing UDK regardless if it was fetched from the primary or secondary, since
      # UDKs are interchangeable between primary and secondary endpoints.
      udk = self.class.get_udk(@uploadable.abs_storage_account_name)
      if !udk.nil? && ((Time.parse(udk.signed_expiry) - Time.now.utc) > @uploadable.storage_download_expiration.to_i)
        return udk
      end

      # Either we did not have yet an UDK or it was gonna expire before the requested expiration
      udk = fetch_user_delegation_key(Time.now.utc, Time.now.utc + [MINIMUM_UDK_TTL, @uploadable.storage_download_expiration.to_i * 2].max + SecureRandom.rand(UDK_FETCH_JITTER))
      self.class.add_udk(@uploadable.abs_storage_account_name, udk)
      udk
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
          "memoryalpha_abs.user_delegation_key.time",
          GitHub::Dogstats.duration(timer_start),
          tags: { "account_name" => @uploadable.abs_storage_account_name, "result" => result, "geoendpoint" => (failover_to_secondary? ? "secondary" : "primary") }
        )
      end
      delegation_key
    end

    def generate_signed_blob_url(expiration = nil)

      # Generate the signed blob URL
      sas_generator = Azure::Storage::Common::Core::Auth::SharedAccessSignature.new(
        @uploadable.abs_storage_account_name,
        "",
        user_delegation_key(expiration)
      )

      sas_token = sas_generator.generate_service_sas_token(
        "#{@uploadable.storage_abs_container}/#{@uploadable.storage_abs_key(self)}",
        {
            service: "b",           # blob
            resource: "b",          # blob
            protocol: "https",
            permissions: "r",       # read-only
            expiry: (Time.now.utc + (@uploadable.storage_download_expiration)).to_s
        }
      )

      "#{base_url}?#{sas_token}"
    end

    def failover_to_secondary?
      return true if FeatureFlag.vexi.enabled?(FEATURE_FLAG_USE_READONLY_SECDONDARY_ENDPOINT, "AzureAccountName:#{@uploadable.abs_storage_account_name}", default: false)
      false
    end

    def storage_account_name_with_primary_or_secondary
      if failover_to_secondary?
        "#{@uploadable.abs_storage_account_name}-secondary"
      else
        @uploadable.abs_storage_account_name
      end
    end

    def blob_client
      # will return either the primary or secondary blob client, depending on the feature flag resolution
      # UDKs fetched from one or the other are interchangeable, and can be used for signing SAS URLs for both
      # primary and secondary endpoints.
      blob_client = self.class.get_blob_client(storage_account_name_with_primary_or_secondary)
      return blob_client unless blob_client.nil?

      azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_azure_environment
      token_provider_settings = MsRestAzure::ActiveDirectoryServiceSettings.get_settings(azure_environment)
      token_provider_settings.token_audience = TOKEN_AUDIENCE
      token_provider = MsRestAzure::ApplicationTokenProvider.new(
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
      self.class.add_blob_client(storage_account_name_with_primary_or_secondary, blob_client)
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
