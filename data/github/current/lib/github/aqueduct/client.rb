# typed: true
# frozen_string_literal: true
#
module GitHub
  module Aqueduct
    class Client < ::Aqueduct::Client
      attr_accessor :circuit_breaker

      def initialize(**kwargs)
        @circuit_breaker = kwargs.delete(:circuit_breaker)
        super
      end
    end
  end
end
