# frozen_string_literal: true

require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"
require "faraday"
require "github-launch"
require "freno/throttler"
require "active_job/scheduled_job"

require "./lib/dependabot/logger"
require "./lib/dependabot/request_logger"

require "./lib/middleware/hmac_authentication_twirp"
require "./lib/dependency_graph/snapshots"
require "./lib/github/twirp"
require "./lib/github/twirp/advisorydb"
require "./lib/github/twirp/autofix"
require "./lib/github/twirp/app_install"
require "./lib/github/twirp/global_id"
require "./lib/github/twirp/dependabot_pull_requests"
require "./lib/github/twirp/dependabot_repository_settings"
require "./lib/github/twirp/tokens"
require "./lib/github/check_run"
require "./lib/turboscan/autofix"
require "./lib/freno/throttler_instrumenter"
require "./lib/active_job/queue_adapters/managed_aqueduct_adapter"
require "./lib/secret_fetcher"
require "./lib/ecosystems"

# report exceptions to Haystack using Failbot
require "failbot/rails"
require "./lib/dependabot/exceptions"
require "./lib/dependabot/failbot_formatter"
Failbot::Config::EXCEPTION_FORMATS[:structured_scrubbed] = Dependabot::FailbotFormatter
ENV["FAILBOT_EXCEPTION_FORMAT"] = "structured_scrubbed"
Failbot::Rails.setup("dependabot-api")

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Dependabot
  class Application < Rails::Application
    config.load_defaults "7.2"

    # Send Active Storage analysis and purge jobs to a dedicated queue.
    config.active_storage.queues.analysis = :active_storage
    config.active_storage.queues.purge = :active_storage

    # Settings in config/environments/* take precedence over those specified
    # here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    config.active_job.queue_adapter = :managed_aqueduct

    config.active_record.schema_format = :sql

    # Disable preloading all features
    config.flipper.preload = false

    config.cache_store = :redis_cache_store, {
      url: ENV["REDIS_URL"],
      password: ENV["REDIS_PASSWORD"],
      # This will auto-invalidate cache on upgrades
      namespace: "dependabot_api_#{Rails.version.tr('.', '_')}_#{RUBY_VERSION.tr('.', '_')}",
    }.compact

    # Use our custom request logger
    config.middleware.swap Rails::Rack::Logger, Dependabot::RequestLogger

    Dependabot::Logger.setup

    def integration_login
      "#{integration_name}[bot]"
    end

    def integration_name
      Prius.get(:github_integration_name)
    end

    def github_dependabot_user_id
      Prius.get(:github_dependabot_user_id)
    end

    def target_github_api_endpoint(account)
      if Dependabot.proxima?
        "https://api.#{target_github_hostname(account)}/"
      elsif Dependabot.enterprise? && !Rails.env.test?
        URI.join(Prius.get(:target_github_url), "api/v3/").to_s
      else
        "https://api.github.com/"
      end
    end

    def target_github_graphql_endpoint
      return "https://api.github.com/graphql" if Rails.env.test?

      if Dependabot.proxima?
        URI.join(Prius.get(:target_github_internal_url), "graphql").to_s
      elsif Dependabot.enterprise?
        URI.join(Prius.get(:target_github_url), "api/graphql").to_s
      else
        URI.join(dotcom_github_internal_api_endpoint, "graphql").to_s
      end
    end

    def target_github_internal_api_endpoint
      # In development, there is no internal api to target
      return development_internal_api_endpoint if Rails.env.development?
      return dotcom_github_internal_api_endpoint if Rails.env.test?

      if Dependabot.proxima?
        Prius.get(:target_github_internal_url)
      elsif Dependabot.enterprise?
        URI.join(Prius.get(:target_github_internal_url).presence || Prius.get(:target_github_url), "api/v3/").to_s
      else
        dotcom_github_internal_api_endpoint
      end
    end

    def target_github_web_endpoint
      Prius.get(:target_github_url)
    end

    def target_github_hostname(account)
      return "#{account.tenant.slug}.ghe.com" if Dependabot.proxima?

      URI.parse(Prius.get(:target_github_url)).host
    end

    def development_internal_api_endpoint
      URI.join(Prius.get(:target_github_url), "api/v3/").to_s
    end

    def dotcom_github_internal_api_endpoint
      "https://internal-api.service.#{Prius.get(:kube_region)}.github.net/"
    end

    def dependabot_actions_api_endpoint(account)
      if Dependabot.proxima?
        "https://dependabot-api.#{account.tenant.slug}.ghe.com"
      elsif Dependabot.enterprise?
        Prius.get(:dependabot_api_endpoint)
      else
        "https://dependabot-actions.githubapp.com"
      end
    end

    def dotcom_proxima_sync_endpoint
      URI.join(Prius.get(:dotcom_dependabot_api_internal_url), "/proxima/sync").to_s
    end

    def github_twirp_client
      @github_twirp_client ||= GitHub::Twirp::Client.new(
        github_api_url: target_github_internal_api_endpoint,
        hmac_key: Prius.get(:github_internal_twirp_hmac_key)
      )
    end

    def global_id_api_client
      @global_id_api_client ||= GitHub::Twirp::GlobalId.new(client: github_twirp_client)
    end

    def dependabot_repository_settings_client
      @dependabot_repository_settings_client ||= GitHub::Twirp::DependabotRepositorySettings.new(
        client: github_twirp_client
      )
    end

    def autofix_client
      @autofix_client ||= GitHub::Twirp::Autofix.new(
        client: github_twirp_client
      )
    end

    def advisorydb_client
      @advisorydb_client ||= GitHub::Twirp::Advisorydb.new(
        client: github_twirp_client
      )
    end

    def kredz_client
      retry_options = {
        max: 2,
        interval: 0.05,
        interval_randomness: 0.5,
        backoff_factor: 2,
        methods: [], # Twirp will use POST so don't filter by default methods
        exceptions: [Faraday::ConnectionFailed],
      }
      hmac_secret = Prius.get(:kredz_hmac_key).split(",").last
      connection = Faraday.new(url: Prius.get(:kredz_addr)) do |conn|
        conn.request :retry, retry_options
        conn.use Middleware::HMACAuthenticationTwirp, hmac_key: hmac_secret
        conn.use MetricsFaradayMiddleware, client: MetricsClient
        conn.adapter Faraday.default_adapter
      end

      GitHub::Launch::Services::Credz::CredentialsServiceClient.new(connection)
    end

    def secret_fetcher
      @secret_fetcher ||= SecretFetcher.new(
        github_integration_node_id: github_integration_global_id,
        kredz: kredz_client,
        global_id_api_client: global_id_api_client,
      )
    end

    def github_integration_global_id
      Dependabot.enterprise? ? Prius.get(:github_integration_node_id) : Prius.get(:github_integration_next_global_id)
    end
  end

  def self.flipper
    ::Flipper.instance
  end

  def self.enterprise?
    Prius.get(:enterprise)
  end

  # Freno is not available in GHES.
  def self.freno_enabled?
    Rails.env.production? && !enterprise?
  end

  def self.freno_throttler
    @freno_throttler ||= Freno::Throttler.new(
      client: Freno.client,
      app: :dependabot_api,
      instrumenter: Freno::ThrottlerInstrumenter.new,
    )
  end

  def self.proxima?
    Prius.get(:proxima_stamp).present?
  end

  def self.redis
    if Prius.get(:redis_password).present?
      Redis.new(password: Prius.get(:redis_password))
    else
      Redis.new
    end
  end
end

require "dependabot/hydro_config"
