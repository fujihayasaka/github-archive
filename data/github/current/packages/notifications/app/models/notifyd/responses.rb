# typed: true
# frozen_string_literal: true

module Notifyd
  module Responses

    class ThreadSubscription < Notifyd::Response
    end

    class Boolean < Notifyd::Response
      def initialize(&block)
        super(false)
      end
    end

  end
end
