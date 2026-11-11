# typed: strict
# frozen_string_literal: true

require "configs"

module Configsd
  module EntryType
    REPOSITORY = "Repository"
    USER = "User"
    BUSINESS = "Business"
    GLOBAL = "Global"
  end

  sig { returns(Configs::Client) }
  def self.client
    @client ||= T.let(Configs::Client.new(build_connection), T.nilable(Configs::Client))
  end

  sig { void }
  def self.reset!
    @client = T.let(nil, T.nilable(Configs::Client))
  end

  sig { params(ownership_chain: Configurations::RepoOwnershipChain, event: T.nilable(String)).void }
  def self.invalidate_cache_for(ownership_chain, event = nil)
    Configsd::Cache::ByTargets.new([ownership_chain]).invalidate(event)
  end

  # Retry lambda for configsd RPCs.  Extends the default RETRY_TWIRP_LAMBDA
  # (which matches Get|List) to also retry Resolve* paths — all of which are
  # idempotent reads.  Future mutating RPCs (Create*, Update*, etc.) will not
  # be retried.
  RETRY_RESOLVE_LAMBDA = T.let(
    lambda { |env, exception|
      GitHub::FaradayClient::RETRY_TWIRP_LAMBDA.call(env, exception) ||
        (env.method == :post && %r{\A/twirp/.*/Resolve[^/]*\z}.match?(env.url.path))
    },
    T.proc.params(env: T.untyped, exception: T.untyped).returns(T::Boolean),
  )

  sig { returns(Faraday::Connection) }
  def self.build_connection
    url = GitHub.service_mesh_enabled? ? GitHub.configsd_mesh_url : GitHub.configsd_url

    GitHub::FaradayClient.internal("configsd", url, request: { timeout: 3 }) do |conn|
      conn.use GitHub::FaradayMiddleware::CallerContext
      conn.use GitHub::FaradayMiddleware::Retries, retry_if: RETRY_RESOLVE_LAMBDA
      # Override the FaradayClient default request_volume_threshold (2) which is
      # far too sensitive for configsd.  During deploys, just 2 slow mesh
      # connections trip the breaker and cascade synthetic 502s to every caller
      # for the duration of the sleep window.  A threshold of 20 (the Resilient
      # gem's own default) requires a statistically meaningful error rate before
      # opening the circuit.
      conn.use GitHub::FaradayMiddleware::Resilient, options: {
        request_volume_threshold: 20,
        error_threshold_percentage: 60,
      }
    end
  end

  private_class_method :build_connection
end
