# typed: false
# frozen_string_literal: true

module Platform
  module Errors
    class RateLimited < Errors::Analysis
      def self.type
        "RATE_LIMITED"
      end

      def initialize(*args, **options)
        super(self.class.type, *args, **options)
      end
    end
  end
end
