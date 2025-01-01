# typed: false
# frozen_string_literal: true

module Platform
  module Errors
    class Unauthorized::Read < Errors::Execution
      def initialize(*args, **options)
        super(self.class.type, *args, **options)
      end

      def self.type
        "UNAUTHORIZED-READ"
      end
    end
  end
end
