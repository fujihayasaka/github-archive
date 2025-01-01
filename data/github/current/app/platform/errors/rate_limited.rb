# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class RateLimited < Errors::Analysis
      def self.type
        "RATE_LIMITED"
      end

      def initialize(*args, **options)
        T.unsafe(Errors::Analysis.instance_method(:initialize)).bind(self).call(self.class.type, *args, **options)
      end
    end
  end
end
