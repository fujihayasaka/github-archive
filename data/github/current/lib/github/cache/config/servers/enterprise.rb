# typed: true
# frozen_string_literal: true

module GitHub
  module Cache
    class Config
      module Servers
        class Enterprise
          sig { returns(T::Array[String]) }
          def servers
            servers = (ENV["ENTERPRISE_MEMCACHE_SERVERS"] || "localhost").split(",")
            servers.map { |server| "#{server}:11211" }
          end
        end
      end
    end
  end
end
