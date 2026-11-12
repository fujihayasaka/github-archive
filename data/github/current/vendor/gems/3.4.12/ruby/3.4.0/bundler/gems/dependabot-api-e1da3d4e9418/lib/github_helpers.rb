# frozen_string_literal: true

require "openssl"
require "rbnacl"
require "etag_cache"

require "github_helpers/client_with_retries"

# rubocop:disable Metrics/ModuleLength
module GitHubHelpers
  DEFAULT_CLIENT_ARGS = {
    connection_options: { request: { open_timeout: 2, timeout: 10 } },
    user_agent: "github/dependabot-api (#{Octokit::Default.user_agent})",
  }.freeze

  CONNECTION_FAILURE_ERRORS = [
    Faraday::ConnectionFailed,
    Faraday::TimeoutError,
    Faraday::SSLError,
    Octokit::BadGateway,
  ].freeze

  RETRYABLE_ERRORS = [
    Octokit::InternalServerError,
    Octokit::ServerError,
    Octokit::AbuseDetected,
    Octokit::TooManyRequests,
    *CONNECTION_FAILURE_ERRORS,
  ].freeze

  class MaxPagesExceeded < StandardError
    attr_reader :pages

    def initialize(pages)
      @pages = pages
      super("Max pages to paginage through exceeded!")
    end
  end

  class InvalidInstallationId < StandardError
    attr_reader :installation_id

    def initialize(installation_id)
      @installation_id = installation_id
      super("Installation ID '#{installation_id}' not found")
    end
  end

  class << self # rubocop:disable Metrics/ClassLength
    def webhook_signature(webhook_body, webhook_secret)
      digest = OpenSSL::Digest.new("sha1")
      hmac = OpenSSL::HMAC.hexdigest(digest, webhook_secret, webhook_body)
      "sha1=#{hmac}"
    end

    def integration_token
      private_pem = Prius.get(:github_integration_private_key)
      private_key = OpenSSL::PKey::RSA.new(private_pem)

      payload = {
        iat: Time.now.to_i,
        exp: 1.minute.from_now.to_i,
        iss: Prius.get(:github_integration_id),
      }

      JWT.encode(payload, private_key, "RS256")
    end

    # This method acts a shim to allow us to fork the token creation process
    # based on an account-level feature flag so we can test using global apps
    def access_token_for(account:, repo_ids: nil, permissions: nil)
      if account.using_global_app?
        global_access_token_for(account.github_id,
                                repo_ids: repo_ids,
                                permissions: permissions)
      else
        installation_access_token_for(account.current_installation_id,
                                      repo_ids: repo_ids,
                                      permissions: permissions)
      end
    end

    def installation_access_token_for(installation_id,
                                      repo_ids: nil,
                                      permissions: nil)
      raise ArgumentError, "Installation ID must not be `nil`" unless installation_id

      cache_key = access_token_cache_key(
        installation_id,
        repo_ids: repo_ids,
        permissions: permissions,
      )

      token = Rails.cache.fetch(cache_key)
      return encrypted_box.decrypt(Base64.strict_decode64(token)) if token

      access_token = create_installation_access_token_for(
        installation_id,
        repo_ids: repo_ids,
        permissions: permissions,
      )

      cache_access_token(cache_key, access_token)
      access_token.token
    end

    def global_access_token_for(target_id,
                                repo_ids: nil,
                                permissions: nil)
      raise ArgumentError, "Target ID must not be `nil`" unless target_id

      cache_key = access_token_cache_key(
        target_id,
        repo_ids: repo_ids,
        permissions: permissions,
        prefix: "global_access_token",
      )

      token = Rails.cache.fetch(cache_key)
      return encrypted_box.decrypt(Base64.strict_decode64(token)) if token

      access_token = create_global_access_token_for(
        target_id,
        repo_ids: repo_ids,
        permissions: permissions,
      )

      cache_access_token(cache_key, access_token)
      access_token.token
    end

    def delete_cached_access_token_for(account:,
                                       repo_ids: nil,
                                       permissions: nil)
      if account.using_global_app?
        delete_cached_global_access_token_for(
          account.github_id,
          repo_ids: repo_ids,
          permissions: permissions,
        )
      else
        delete_cached_installation_access_token_for(
          account.current_installation_id,
          repo_ids: repo_ids,
          permissions: permissions,
        )
      end
    end

    def delete_cached_installation_access_token_for(installation_id,
                                                    repo_ids: nil,
                                                    permissions: nil)
      cache_key = access_token_cache_key(
        installation_id,
        repo_ids: repo_ids,
        permissions: permissions,
      )
      Rails.cache.delete(cache_key)
    end

    def delete_cached_global_access_token_for(target_id,
                                              repo_ids: nil,
                                              permissions: nil)
      cache_key = access_token_cache_key(
        target_id,
        repo_ids: repo_ids,
        permissions: permissions,
        prefix: "global_access_token",
      )
      Rails.cache.delete(cache_key)
    end

    def with_connection_failure_retrying(max_retries = 1)
      retry_attempt = 0

      begin
        yield
      rescue *CONNECTION_FAILURE_ERRORS
        retry_attempt += 1
        retry_attempt <= max_retries ? retry : raise
      end
    end

    def fetch_all_pages(client:, method:, args: [], headers: {},
                        transform: nil, max_pages: nil)
      client.public_send(method, *args)
      check_max_pages_not_exceeded(max_pages, client.last_response)

      next_link = client.last_response.rels[:next]
      response = client.last_response
      pages = transform ? transform.call(response) : [response]

      while next_link
        with_connection_failure_retrying do
          next_page = next_link.get(headers: headers)
          pages += transform ? transform.call(next_page) : [next_page]
          next_link = next_page.rels[:next]
        end
      end

      pages
    rescue Zlib::BufError
      retrying ||= false
      raise if retrying

      retrying = true
      retry
    end

    def octokit_client_for(options = {})
      Octokit::Client.new(DEFAULT_CLIENT_ARGS.merge(options))
    end

    def onboard_account_with_global_app?(github_id:)
      return true if Prius.get(:global_app_onboarding)

      Dependabot::Application.monolith_feature_enabled?(
        feature: :dependabot_global_app_onboarding,
        actor: MonolithFeatureFlags::RawActor.new(FeatureFlags::Actor::User.new(github_id)),
        use_cache: true,
      )
    end

    def create_proxima_integration_access_token(repo: nil)
      proxima_service_identity_token(repo) if repo
    end

    def proxima_service_identity_token(repo)
      secret = Prius.get(:proxima_service_identity_secret_key)

      payload = {
        iat: Time.now.to_i - 10,
        exp: 1.hour.from_now.to_i,
        aud: "api.github.com",
        stamp: Prius.get(:proxima_stamp),
        service_name: "dependabot",
        tenant_shortcode: repo.account.shortcode || fallback_shortcode(repo),
      }

      JWT.encode(payload, secret, "HS256", { typ: "JWT" })
    end

    def fallback_shortcode(repo)
      Dependabot::Logger.info(
        msg: "Shortcode not provided, using fallback value",
        stamp: Prius.get(:proxima_stamp),
        repo: repo.id,
        account: repo.account.id,
      )

      Prius.get(:proxima_stamp)
    end

    private

    def create_installation_access_token_for(installation_id,
                                             repo_ids: nil,
                                             permissions: nil)
      tags = { global: false, repo_ids_bucket: bucket_repo_ids(repo_ids) }
      MetricsClient.time("create_access_token", tags: tags) do
        api_endpoint = Dependabot::Application.target_github_internal_api_endpoint
        client_args = {
          api_endpoint: api_endpoint,
          bearer_token: integration_token,
        }
        client = octokit_client_for(client_args)

        options = {
          accept: "application/vnd.github.machine-man-preview+json",
          repository_ids: repo_ids,
          permissions: permissions,
        }.compact

        return with_connection_failure_retrying do
          client.create_app_installation_access_token(installation_id, options)
        end
      end
    rescue Octokit::NotFound
      # Installation ID no longer valid
      raise InvalidInstallationId, installation_id
    end

    def create_global_access_token_for(target_id,
                                       repo_ids: nil,
                                       permissions: nil)
      tags = { global: true, repo_ids_bucket: bucket_repo_ids(repo_ids) }
      MetricsClient.time("create_access_token", tags: tags) do
        api_endpoint = Dependabot::Application.target_github_internal_api_endpoint
        client_args = {
          api_endpoint: api_endpoint,
          bearer_token: integration_token,
        }
        client = octokit_client_for(client_args)

        options = {
          target_id: target_id,
          accept: "application/vnd.github.machine-man-preview+json",
          repository_ids: repo_ids,
          permissions: permissions,
        }.compact

        return with_connection_failure_retrying do
          client.post("app/global/access_tokens", options)
        end
      end
    end

    def check_max_pages_not_exceeded(max_pages, last_response)
      return unless max_pages
      return unless last_response.rels[:last]

      last_page_url = URI.parse(last_response.rels[:last].href)
      pages = CGI.parse(last_page_url.query).
              fetch("page", [1]).first.to_i
      raise MaxPagesExceeded.new(pages: pages) if pages > max_pages
    end

    def cache_access_token(cache_key, access_token)
      # Cache an encrypted copy of the access token. Note that the 45 minute
      # grace period we give ourselves matches the time-to-live for our update
      # jobs (to ensure the token doesn't expire whilst in use).
      raise "Access token will expire in less than 45 minutes!" if access_token.expires_at - Time.now.utc < 45.minutes

      Rails.cache.write(
        cache_key,
        Base64.strict_encode64(encrypted_box.encrypt(access_token.token)),
        expires_in: access_token.expires_at - Time.now.utc - 45.minutes,
      )
    end

    def encrypted_box
      encryption_key = Base64.strict_decode64(Prius.get(:redis_encryption_key))
      RbNaCl::SimpleBox.from_secret_key(encryption_key)
    end

    def access_token_cache_key(target_id,
                               repo_ids: nil,
                               permissions: nil,
                               prefix: "installation_access_token")
      cache_key = "#{prefix}/#{target_id}"
      cache_key += "/#{repo_ids.join('-')}" if repo_ids
      cache_key += permissions.sort.map { |k, v| "#{k}=#{v}" }.join("&") if permissions
      cache_key
    end

    def bucket_repo_ids(repo_ids)
      case repo_ids&.length
      when nil
        0
      when 0..3
        repo_ids.length
      when 4..10
        4
      else
        (repo_ids.length / 10) * 10
      end
    end
  end
end
# rubocop:enable Metrics/ModuleLength
