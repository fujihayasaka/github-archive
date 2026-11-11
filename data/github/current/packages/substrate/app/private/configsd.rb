# typed: strict
# frozen_string_literal: true

require "configs"
require "github/faraday_adapter/persistent_excon"

module Configsd
  module EntryType
    REPOSITORY = "Repository"
    USER = "User"
    BUSINESS = "Business"
    GLOBAL = "Global"
  end

  sig { returns(Configs::Client) }
  def self.client
    @client ||= T.let(Configs::Client.new(connection), T.nilable(Configs::Client))
  end

  sig { returns(Faraday::Connection) }
  def self.connection
    url = GitHub.service_mesh_enabled? ? GitHub.configsd_mesh_url : GitHub.configsd_url
    GitHub::FaradayClient.persistent_internal("configsd", url, request: { timeout: 3 }) do |conn|
      conn.adapter_options = [{ timeout: 3 }]
    end
  end

  sig { params(ownership_chain: Configurations::RepoOwnershipChain, event: T.nilable(String)).void }
  def self.invalidate_cache_for(ownership_chain, event = nil)
    Configsd::Cache::ByTargets.new([ownership_chain]).invalidate(event)
  end

  private_class_method :connection
end
