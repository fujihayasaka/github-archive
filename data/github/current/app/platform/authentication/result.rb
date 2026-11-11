# typed: true
# frozen_string_literal: true

module Platform
  module Authentication
    class Result
      attr_reader :success, :assertion, :failure_type
      attr_accessor :user_data, :redirect_url

      def success?
        success
      end

      def failure?
        !success?
      end

      def unauthorized?
        failure? && failure_type == :unauthorized
      end

      def invalid?
        failure? && failure_type == :invalid
      end
    end
  end
end
