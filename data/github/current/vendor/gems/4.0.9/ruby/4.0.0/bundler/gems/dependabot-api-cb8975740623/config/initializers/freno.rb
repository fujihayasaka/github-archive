# frozen_string_literal: true

require "faraday"
require "freno/client"
require "freno/fake_client"

module Freno
  DEFAULT_FRENO_URL = "http://freno.service.github.net:8111"
  DEPENDABOT_CLUSTER = :dependabot

  def self.client
    @client ||= client_class.new(faraday) do |freno|
      freno.default_app = :"dependabot-api"
      freno.default_store_name = :"dependabot-api"
      freno.default_store_type = :mysql
    end
  end

  def self.client=(client)
    @client = client
  end

  def self.client_class
    return Client if Dependabot.freno_enabled?

    FakeClient
  end
  private_class_method :client_class

  def self.faraday
    Faraday.new(freno_url) do |faraday|
      faraday.options[:open_timeout] = 5.0
      faraday.options[:timeout] = 5.0
      faraday.adapter Faraday::Adapter::NetHttp
    end
  end
  private_class_method :faraday

  def self.freno_url
    @freno_url ||= ENV["FRENO_URL"] || DEFAULT_FRENO_URL
  end
end
