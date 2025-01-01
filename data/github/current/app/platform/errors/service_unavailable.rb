# typed: false
# frozen_string_literal: true

module Platform
  module Errors
    class ServiceUnavailable < Errors::Execution
      ERROR_TYPE = "SERVICE_UNAVAILABLE"

      def initialize(*args, **options)
        super(ERROR_TYPE, *args, **options)
      end

      def self.type
        ERROR_TYPE
      end
    end
  end
end
