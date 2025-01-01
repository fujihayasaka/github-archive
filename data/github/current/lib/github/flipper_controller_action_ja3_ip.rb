# typed: true
# frozen_string_literal: true

# Allows controller/action/ja3 and controller/action/ip combinations to be used as
# Flipper actors. For example, "Blocker:commit-show-127.0.0.1"
module GitHub
  class FlipperEndpointJa3Ip
    include GitHub::FlipperActor
    include GitHub::VexiActor

    def initialize(controller, action, ja3_or_ip)
      @controller = controller
      @action = action
      @ja3_or_ip = ja3_or_ip

      freeze
    end

    def ==(other)
      self.class == other.class && vexi_id == other.vexi_id
    end
    alias_method :eql?, :==

    def flipper_id
      "Blocker:#{@controller}-#{@action}-#{@ja3_or_ip}"
    end

    def vexi_id
      flipper_id
    end
  end
end
