# frozen_string_literal: true

require "faraday"
require "dependency_graph/faraday_client/internal"

require "freno/client"
require "freno/fake_client"
require "freno/throttler"

module Freno
  def self.client
    client_class = self.freno_url.blank? ? FakeClient : Client

    @client ||= client_class.new(faraday) do |freno|
      freno.default_app = :dependency_graph
      freno.default_store_name = :"dependency-graph"
      freno.default_store_type = :mysql
    end
  end

  def self.faraday
    DependencyGraph::FaradayClient::Internal.new(self.freno_url) do |faraday|
      faraday.use GitHub::FaradayMiddleware::Datadog, stats: Rails.application.stats, service_name: "freno"
      faraday.options[:open_timeout] = 5.0
      faraday.options[:timeout] = 5.0
    end
  end

  def self.freno_url
    ENV["FRENO_URL"]
  end
end
