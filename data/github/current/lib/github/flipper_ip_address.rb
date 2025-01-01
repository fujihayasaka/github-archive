# typed: true
# frozen_string_literal: true

# Allows IP addresses (e.g., 127.0.0.1) to be used as
# Flipper actors.
module GitHub
  class FlipperIpAddress
    include GitHub::FlipperActor
    include GitHub::VexiActor

    def initialize(ip_address)
      @ip_address = ip_address
      freeze
    end

    def ==(other)
      self.class == other.class && vexi_id == other.vexi_id
    end
    alias_method :eql?, :==

    def flipper_id
      "IP:#{@ip_address}"
    end

    def vexi_id
      flipper_id
    end
  end
end
