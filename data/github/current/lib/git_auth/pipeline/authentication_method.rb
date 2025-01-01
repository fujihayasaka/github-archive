# typed: true
# frozen_string_literal: true

module GitAuth
  class Pipeline
    class AuthenticationMethod
      attr_reader :input
      def initialize(input:)
        @input   = input
      end

      def perform
        process if applicable?
      end

      def result
        return @result if @result

        @result = Result.new(input)
        perform
        @result
      end

      protected

      def hash_token(token)
        Digest::SHA256.base64digest(token)
      end

      private

      def applicable?
        false
      end

      def process
      end
    end
  end
end
