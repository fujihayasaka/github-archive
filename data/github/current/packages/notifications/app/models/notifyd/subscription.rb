# typed: true
# frozen_string_literal: true

module Notifyd
  module Subscription
    include Kernel

    def ignored?
      raise "Not implemented"
    end

    def valid?
      raise "Not implemented"
    end

    def subscribed?
      raise "Not implemented"
    end

    def reason
      raise "Not implemented"
    end

    def events_only?
      raise "Not implemented"
    end

    def list
      raise "Not implemented"
    end
  end
end
