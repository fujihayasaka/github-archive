# frozen_string_literal: true
require "faraday"
require "freno/client"
require "freno/fake_client"
require "freno/replication_delay_cache_decorator"

module Freno

  DEFAULT_FRENO_URL = "https://freno-internal.service.iad.github.net"

  def self.client
    @client ||= client_class.new(faraday) do |freno|
      freno.default_app = :github
      freno.default_store_type = :mysql
      freno.default_store_name = :mysql1
      freno.options[:raise_on_timeout] = false
      freno.decorate :replication_delay, with: ReplicationDelayCacheDecorator.new(cache: Rails.cache, ttl: 1.second, expires_at_millis: 50)
    end
  end

  def self.client=(client)
    @client = client
  end

  def self.client_class
    return Client if GitHub.freno_enabled?
    FakeClient
  end
  private_class_method :client_class

  def self.faraday
    Faraday.new(self.freno_url) do |faraday|
      faraday.options[:open_timeout] = 0.2
      faraday.options[:timeout] = 0.2
      faraday.adapter :persistent_excon
    end
  end
  private_class_method :faraday

  def self.freno_url
    @freno_url ||= (GitHub.environment["FRENO_URL"] || DEFAULT_FRENO_URL)
  end
end
