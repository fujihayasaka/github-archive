# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class ServiceUnavailable < Errors::Execution
      ERROR_TYPE = "SERVICE_UNAVAILABLE"

      def initialize(*args, **options)
        T.unsafe(Errors::Execution.instance_method(:initialize)).bind(self).call(ERROR_TYPE, *args, **options)
      end

      def self.type
        ERROR_TYPE
      end
    end
  end
end
