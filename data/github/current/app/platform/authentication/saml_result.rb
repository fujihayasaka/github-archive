# typed: true
# frozen_string_literal: true

module Platform
  module Authentication
    class SamlResult < Platform::Authentication::Result
      def initialize(success:, assertion:, failure_type: nil)
        @success = success
        @assertion = assertion
        @failure_type = failure_type
      end

      def self.authorized(assertion)
        new(success: true, assertion: assertion)
      end

      def self.unauthorized(assertion)
        new(success: false, failure_type: :unauthorized, assertion: assertion)
      end

      def self.invalid(assertion)
        new(success: false, failure_type: :invalid, assertion: assertion)
      end

      def errors
        return [] unless failure?
        assertion.errors.map do |error|
          case error
          when String
            error
          when Nokogiri::XML::SyntaxError
            error.message
          end
        end
      end
    end
  end
end
