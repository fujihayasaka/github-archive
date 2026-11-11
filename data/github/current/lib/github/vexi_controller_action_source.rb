# typed: true
# frozen_string_literal: true

# Allows controller/action/source combinations to be used as feature flag actors,
# where source is either a JA3 fingerprint, JA4 fingerprint, JA4H fingerprint or
# an IP address. For example, "Blocker:commit-show-127.0.0.1".
module GitHub
  class VexiControllerActionSource
    include GitHub::VexiActor

    def initialize(controller, action, source)
      @controller = controller
      @action = action
      @source = source
    end

    def ==(other)
      self.class == other.class && vexi_id == other.vexi_id
    end
    alias_method :eql?, :==

    # Feature Flag Actor ID. For example, "Blocker:commit-show-127.0.0.1"
    def vexi_id
      "Blocker:#{@controller}-#{@action}-#{@source}"
    end
  end
end
