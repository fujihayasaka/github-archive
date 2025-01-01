# typed: false
# frozen_string_literal: true

module Platform
  module Errors
    class Unauthorized::Write < Errors::Execution
      def initialize(*args, **options)
        super(self.class.type, *args, **options)
      end

      def self.type
        "UNAUTHORIZED-WRITE"
      end
    end
  end
end
