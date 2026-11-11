# typed: strict
# frozen_string_literal: true

require "configs"
require "github/faraday_adapter/persistent_excon"

module Configsd

  sig { returns(Configs::Client) }
  def self.client
    @client ||= T.let(Configs::Client.new(connection), T.nilable(Configs::Client))
  end

  sig { returns(Faraday::Connection) }
  def self.connection
    @connection ||= T.let(Faraday.new(GitHub.service_mesh_enabled? ? GitHub.configsd_mesh_url : GitHub.configsd_url) do |conn| # rubocop:disable GitHub/RequireExplicitInternalOrExternalFaradayClientWrapper
      conn.options[:open_timeout] = 0.15
      conn.options[:timeout] = 0.5

      conn.use GitHub::FaradayMiddleware::RequestID
      conn.use GitHub::FaradayMiddleware::Datadog,
        stats: GitHub.dogstats,
        service_name: "configsd"
      conn.use GitHub::FaradayMiddleware::Retries
      conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.configsd_hmac_key

      conn.adapter :persistent_excon
    end, T.nilable(Faraday::Connection))
  end

  sig { params(ownership_chain: Configurations::RepoOwnershipChain, event: T.nilable(String)).void }
  def self.invalidate_cache_for(ownership_chain, event = nil)
    return unless FeatureFlag.vexi.enabled?(:remote_cache_configs_invalidate, default: false)

    Configsd::Cache::ByTargets.new([ownership_chain]).invalidate(event)
  end
end
