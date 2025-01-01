# typed: true
# frozen_string_literal: true

class IntegrationInstallation
  module ApiParamsValidators
    class Error < StandardError
      attr_reader :reason

      def initialize(message, reason = nil)
        @reason = reason
        super(message)
      end

    end
  end
end
