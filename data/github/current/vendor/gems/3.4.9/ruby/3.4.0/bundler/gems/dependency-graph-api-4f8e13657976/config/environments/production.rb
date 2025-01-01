require "active_support/core_ext/integer/time"
require_relative "../../lib/hmac_authentication"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = true

  # Disable serving static files from the `/public` folder by default since
  # Apache or NGINX already handles this.
  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?

  # Sets the HMAC key used to verify request bodies sent to the Dependency Graph API.
  config.dependency_graph_api_hmac_keys = ENV["DEPENDENCY_GRAPH_API_HMAC_KEYS"].to_s.split(" ")

  # Sets the HMAC key used to communicate with dependency-graph-platform.
  config.dependency_graph_platform_hmac_keys = ENV["DEPENDENCY_GRAPH_PLATFORM_HMAC_KEYS"].to_s.split(" ")

  config.dependency_snapshots_api_url = ENV.fetch("DEPENDENCY_SNAPSHOTS_API_URL", "https://dependency-snapshots-api-production.service.iad.github.net")

  config.dependency_graph_platform_url = ENV.fetch("DEPENDENCY_GRAPH_PLATFORM_URL", "https://dependency-graph-platform-production.service.iad.github.net")

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.action_controller.asset_host = 'http://assets.example.com'

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = 'X-Sendfile' # for Apache
  # config.action_dispatch.x_sendfile_header = 'X-Accel-Redirect' # for NGINX

  # Mount Action Cable outside main process or domain
  # config.action_cable.mount_path = nil
  # config.action_cable.url = 'wss://example.com/cable'
  # config.action_cable.allowed_request_origins = [ 'http://example.com', /http:\/\/example.*/ ]

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # config.force_ssl = true

  # This log level is set by the the GITHUB_TELEMETRY_LIB_LOG_LEVEL environment variable.
  # config.log_level = :info

  # Prepend all log lines with the following tags.
  config.log_tags = [:request_id]

  # Use a different cache store in production.
  # config.cache_store = :mem_cache_store

  if ENV["DEPENDENCY_GRAPH_REDIS_CACHE_URL"].blank?
    DependencyGraph.logger.warn("DEPENDENCY_GRAPH_REDIS_CACHE_URL is not present. Rails cache is DISABLED in this environment.")
  else
    config.cache_store = :redis_cache_store, {
      url: ENV.fetch("DEPENDENCY_GRAPH_REDIS_CACHE_URL"),

      # Username and password are mandatory for production environments
      username: ENV.fetch("DEPENDENCY_GRAPH_REDIS_CACHE_USERNAME"),
      password: ENV.fetch("DEPENDENCY_GRAPH_REDIS_CACHE_PASSWORD"),

      error_handler: DependencyGraph.rails_cache_error_handler
    }
  end

  config.action_mailer.perform_caching = false

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Add middleware for HMAC authentication.
  config.middleware.insert_before Rack::Sendfile, HMACAuthentication

  # The `database_selector` hash is used to pass options to the DatabaseSelector
  # middleware. The `delay` is used to determine how long to wait after a write
  # to send a subsequent read to the primary.
  #
  # The `database_resolver` class is used by the middleware to determine which
  # database is appropriate to use based on the time delay.
  #
  # The `database_resolver_context` class is used by the middleware to set
  # timestamps for the last write to the primary. The resolver uses the context
  # class timestamps to determine how long to wait before reading from the
  # replica.
  #
  # By default Rails will store a last write timestamp in the session. The
  # DatabaseSelector middleware is designed as such you can define your own
  # strategy for connection switching and pass that into the middleware through
  # these configuration options.
  # config.active_record.database_selector = { delay: 2.seconds }
  # config.active_record.database_resolver = ActiveRecord::Middleware::DatabaseSelector::Resolver
  # config.active_record.database_resolver_context = ActiveRecord::Middleware::DatabaseSelector::Resolver::Session
end
