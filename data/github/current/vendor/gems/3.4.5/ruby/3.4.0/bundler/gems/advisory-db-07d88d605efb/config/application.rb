# frozen_string_literal: true

require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
require "sprockets/railtie"
require "rails/test_unit/railtie"

# Preload ActionController exceptions we may want Failbot to ignore
# See https://github.com/rails/rails/issues/44936
require "action_controller/metal/exceptions"

# Report exceptions to Sentry using Failbot
ENV["FAILBOT_BACKEND"] ||= "memory"
require "failbot/rails"

# This probably looks a little bit weird. Turns out, everything in FAILBOT_IGNORED_ERROR_CLASSES needs
# to be resolvable at the time you call .setup.
require_relative "../lib/advisory_db/publication_held_error"

# Similar to gh/gh, we instrument failbot errors out to activesupport notifications
Failbot.instrumenter = ActiveSupport::Notifications

# This approach seemed like a good idea, from https://github.com/github/ninesapp/blob/3071214eea6a134f5cc6bb6788c378ab3b3ddb02/config/application.rb#L21
ENV["FAILBOT_IGNORED_ERROR_CLASSES"] = %w[
  ActionController::UnknownHttpMethod
  AdvisoryDB::PublicationHeldError
].join(",")
Failbot::Rails.setup("advisory-db")

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# bootstrap logging output for github-telemetry-ruby
require "github/telemetry/logs"

module AdvisoryDB
  class Application < Rails::Application
    require "advisory_db/config"
    require "set_forwarded_headers"

    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.

    config.active_record.schema_format = :sql

    config.autoload_paths << "lib/hydro_processors"
    config.autoload_paths << "lib"
    config.eager_load_paths << "lib/hydro_processors"
    config.eager_load_paths << "lib"

    # When protecting requests from CSRF, we need to skip the origin check
    # because authentication via Okta has the nasty side effect of producing an
    # origin mismatch. The HTTP origin header is set to:
    #
    #   https://advisory-inbox.githuapp.com
    #
    # but request.base_url is:
    #
    #   https://advisory-inbox-production.service.ac4-iad.github.net
    #
    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # Skipping the origin check allows us to preserve CSRF protection. This is
    # the same strategy used in github/github for GHES instances.
    config.action_controller.forgery_protection_origin_check = false

    # Fix Rails' URL generation and redirection when serving requests through
    # the Okta Network Gateway.
    config.before_initialize do
      config.middleware.use SetForwardedHeaders
    end

    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    config.active_record.yaml_column_permitted_classes = [
      ::ActiveModel::Type::Binary::Data,
      ::ActiveRecord::Type::Time::Value,
      ::ActiveSupport::HashWithIndifferentAccess,
      ::ActiveSupport::TimeWithZone,
      ::ActiveSupport::TimeZone,
      ::BigDecimal,
      ::Date,
      ::Symbol,
      ::Time,
    ]

    config.after_initialize do
      # make sure that getting a hydro publisher doesn't throw. This is a very basic CYA to protect against deploying with misconfiguration.
      AdvisoryDB.hydro_publisher
    end
  end
end

at_exit do
  if defined?(GitHub::Telemetry)
    GitHub::Telemetry.shutdown
  end
end

require "primer/view_components"
