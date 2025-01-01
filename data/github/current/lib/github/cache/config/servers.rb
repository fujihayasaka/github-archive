# typed: true
# frozen_string_literal: true

module GitHub
  module Cache
    class Config
      module Servers
        autoload :Dotcom, "github/cache/config/servers/dotcom"
        autoload :Enterprise, "github/cache/config/servers/enterprise"
        autoload :Proxima, "github/cache/config/servers/proxima"
        autoload :Default, "github/cache/config/servers/default"
      end
    end
  end
end
