# typed: true
# frozen_string_literal: true

class ConnectionInfo
  attr_reader :host, :url, :config_host
  attr_reader :connection_class, :connection_role

  def initialize(host: nil, url: nil, config_host: nil, connection_class: nil, connection_role: nil)
    @host = host
    @url = url
    @config_host = config_host
    @connection_class = connection_class
    @connection_role = connection_role
  end
end
