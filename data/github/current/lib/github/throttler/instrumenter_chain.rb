# typed: true
# frozen_string_literal: true

require "github/throttler/instrumenter"

module GitHub
  module Throttler
    class InstrumenterChain

      # instrumenter.instrument("throttler.#{event_name}", payload, &block
      def initialize(instrumenters: [])
        @instrumenters = instrumenters
      end

      def register(instrumenter)
        @instrumenters << instrumenter
      end

      def instrument(event_name, payload)
        @instrumenters.each do |instrumenter|
          instrumenter.instrument(event_name, payload)
        end
      end
    end
  end
end
