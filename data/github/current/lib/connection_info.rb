# typed: true
# frozen_string_literal: true

class ConnectionInfo
  attr_reader :host, :url, :connection_class, :connection_role

  def initialize(host: nil, url: nil, connection_class: nil, connection_role: nil)
    @host = host
    @url = url
    @connection_class = connection_class
    @connection_role = connection_role
  end

  def config_host
    return @config_host if defined?(@config_host)
    @config_host = self.class.config_host(url)
  end

  def self.config_host(url)
    return nil if url.nil?
    return @config_host_map[url] if defined?(@config_host_map) && @config_host_map.has_key?(url)

    @config_host_map ||= {}
    @config_host_map[url] = Addressable::URI.parse("mysql://#{url}").host
  end
end
