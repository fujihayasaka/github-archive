# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class TradeControls < Errors::Execution
      TYPE = "TRADE_CONTROLS"
      def initialize(message)
        super(TYPE, message)
      end
    end
  end
end
