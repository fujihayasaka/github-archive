require "./lib/kernel_warning_override"
require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
# require "sprockets/railtie"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

require "./lib/dependency_graph"
require "./lib/dependency_graph_api"
require "./lib/failbot_rails"
require "./lib/logging"
require "./lib/rack/request_logger"
require "./lib/one_off_importers"
require "./lib/aqueduct/aqueduct_config"
require "./lib/aqueduct/aqueduct_adapter"
require "./lib/dependency_graph/database_misconfigured_warning_middleware"
require "github/telemetry/logs"

require "socket"
FailbotRails.setup("dependency-graph-api", { server: Socket.gethostname })

require "datadog/statsd"
require "./lib/vendor_detection"

module DependencyGraph
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 6.1
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    #####
    # This is a default setting added in Rails 7.1, but our lib/ directory has a whole
    # bunch of stuff that does not conform to Zeitwerk/the autoloader's expectations.

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # config.autoload_lib(ignore: %w(tasks))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    config.eager_load_paths << Rails.root.join("etl")
    config.eager_load_paths << Rails.root.join("graphql")

    config.active_record.schema_format = :sql

    # Zeitwork doesn't play nice with ruby-protobuf, so manual loading is required
    $LOAD_PATH << "#{Rails.root}/proto"
    Dir.glob(File.expand_path("proto/hydro/schemas/**/*.rb", Rails.root)).each do |schema_file|
      require schema_file
    end

    if Rails.env.development?
      # We need this middleware to land first, since rails will bail
      # with no DB.
      config.middleware.insert_before 0, DependencyGraph::DatabaseMisconfiguredWarningMiddleware
    end

    if Rails.env.production? || ENV["RAILS_LOG_TO_STDOUT"]
      # Include our request logging middleware.
      config.middleware.use Rack::RequestLogger
    end

    # Abort requests after 120 seconds
    config.middleware.insert_before Rack::Runtime, Rack::Timeout, service_timeout: 120

    # By default, Rack::Timeout logs with the Rails framework logger
    # Switch this to using a named GitHub::Telemetry logger
    Rack::Timeout::Logger.logger = GitHub::Telemetry::Logs.logger("Rack::Timeout")

    # report timeouts to datadog
    Rack::Timeout.register_state_change_observer(:metrics) do |env|
      if env["rack-timeout.info"].state == :timed_out
        Instrument.increment("rack_timeout.timed_out")
      elsif env["rack-timeout.info"].state == :expired
        Instrument.increment("rack_timeout.expired")
      end
    end

    # We need to set this flag because we use an older version of the GraphQL-Ruby library
    config.telemetry.instrumentation = {
      "OpenTelemetry::Instrumentation::GraphQL" => { legacy_tracing: true },
    }

    config.telemetry.enable_span_event_log_exporter = true

    # Use a real queuing backend for Active Job (and separate queues per environment)
    config.active_job.queue_adapter     = ActiveJob::QueueAdapters::AqueductAdapter.new
    config.active_job.queue_name_prefix = "dependency-graph_#{Rails.env}"

    # Using this until we have a recent enough Rails
    # with https://github.com/rails/rails/pull/40213.
    if Rails::VERSION::MAJOR == 6 && Rails::VERSION::MINOR == 1
      ActiveSupport::Digest.hash_digest_class = OpenSSL::Digest::SHA256
    else
      config.active_support.use_digest_class = OpenSSL::Digest::SHA256
    end

    # If Rails message encryption or cookies are ever used, we want to make sure
    # that authenticated encryption is turned on for when that happens.
    config.action_dispatch.use_authenticated_cookie_encryption = true
    config.action_dispatch.use_cookies_with_metadata = true
    config.active_support.use_authenticated_message_encryption = true

    # Rails 7.0+ introduced a new, more compact cache format (which we may or may not use, but this silences a log message)
    config.active_support.cache_format_version = 7.0

    # Rails 8.1 will introduce a new behavior where `to_time` will always preserve the full timezone rather than offset of the receiver
    # By setting this config to :offset we opt out of the new behavior, but we will be opted in automatically once we upgrade to 8.1
    # TODO: change config value to :zone and test before upgrading to 8.1
    config.active_support.to_time_preserves_timezone = :offset

    def stats
      @statsd ||= statsd(namespace: "dependency_graph")
    end

    def unprefixed_stats
      @unprefixed_statsd ||= statsd
    end

    # Internal: Constructs a new Datadog::Statsd instance.
    #
    # namespace: The optional namespace to use as a prefix for all stats
    #            (default: nil).
    def statsd(namespace: nil)
      config = Rails.application.config_for(:dogstatsd)

      # Construct an Array of tags to pass on every Datadog stat
      tags = []
      tags << "pod_type:#{ENV['DG_POD_TYPE']}" if ENV["DG_POD_TYPE"]

      options = { tags: tags }
      options[:namespace] = namespace if namespace.present?

      Datadog::Statsd.new(config.fetch(:host), config.fetch(:port), **options)
    end

    def post_daemonization_hook
      # Reopen statsd file descriptors after daemonization
      @statsd = nil
      stats
    end

    def fast_api_host?
      pod_type = ENV["DG_POD_TYPE"]&.downcase

      if pod_type && pod_type == "api"
        true
      elsif pod_type && pod_type != "api"
        false
      else
        # TODO: Remove this original code once AWS API boxes are decommissioned
        !!`hostname`[/^dependencygraph-api/]
      end
    end
  end

  def self.throttler
    @throttler ||= Freno::Throttler.new(
      client: Freno.client,
      app: :dependency_graph,
      instrumenter: ActiveSupport::Notifications,
      max_wait_seconds: 20,
    )
  end

  def self.aqueduct
    @aqueduct_config ||= DependencyGraph::Aqueduct::AqueductConfig.new(
      api_key: ENV["AQUEDUCT_API_KEY"],
      api_key_version: ENV["AQUEDUCT_API_KEY_VERSION"],
      send_hmac_secret: ENV["AQUEDUCT_DEPENDENCY_GRAPH_SEND_SECRET"],
      receive_hmac_secrets: ENV["AQUEDUCT_DEPENDENCY_GRAPH_RECEIVE_SECRETS"]
    )
  end
end

at_exit do
  if defined?(GitHub::Telemetry)
    GitHub::Telemetry.shutdown
  end
end
