# typed: true
# frozen_string_literal: true

# Require our custom ActiveSupport::Notifications config as early
# as possible so that we specify our notifier before any code starts
# subscribing to events.
require "github/config/notifications"
require "notifyd-client"

# NOTE: (@franciscoj 22/11/2022) we load `notifyd/proto` separated from
# `notifyd-client` because otherwise sorbet creates inferred RBIs for our
# protobuf definitions instead of the ones from the tapioca's DSL generation.
#
# This is not ideal and we most likely want it to be done differently but we'll
# find a better way once the sorbet support in the monolith evolves.
require "notifyd/proto"

module Notifyd
  # Null client that safely handles all method calls when notifyd URL is not configured.
  # This prevents NoMethodError when code calls client.maintenance.delete_user, etc.
  # Returns self for method chaining (e.g., client.maintenance.delete_user) and
  # returns nil for `.error` to indicate success in the ResponseHandler.
  class NullClient
    def method_missing(method_name, *args, &block)
      self
    end

    def respond_to_missing?(method_name, include_private = false)
      true
    end

    # Return nil for error to indicate success in ResponseHandler
    def error
      nil
    end
  end

  def self.client
    notifyd_url = GitHub.notifyd_production_url

    if notifyd_url.blank?
      return NullClient.new if GitHub::AppEnvironment.test? || GitHub::AppEnvironment.development?
      raise "NOTIFYD_PRODUCTION_URL must be configured"
    end

    Notifyd::Client.new(url: notifyd_url, hmac_key: GitHub.notifyd_hmac_key) do |build|
      build.conn.use GitHub::FaradayMiddleware::Resilient, name: "notifyd", options: {
        instrumenter: GitHub,

        # Seconds after tripping circuit before allowing retry
        sleep_window_seconds: 5,

        # % of "marks" that must be failed to trip the circuit
        error_threshold_percentage: 25,

        # Number of seconds in the statistical window
        window_size_in_seconds: 60,

        # Size of buckets in statistical window
        bucket_size_in_seconds: 10,
      }

      build.use_retry(stats: GitHub.dogstats)
      build.conn.use GitHub::FaradayMiddleware::RequestID
      build.conn.use GitHub::FaradayMiddleware::TenantContext

      build.use_adapter(:persistent_excon,
        tcp_nodelay: true,
        keepalive: {
          time: 60,
          intvl: 5,
          probes: 3,
        }
      )
    end
  end
end
