# typed: strict
# frozen_string_literal: true

class Integration
  module Transfers
    class Result < T::Struct
      const :success, T::Boolean
      const :integration, T.nilable(Integration)
      const :message, T.nilable(String)

      sig { params(integration: Integration, message: String).returns(Result) }
      def self.success(integration, message)
        new(success: true, integration: integration, message: message)
      end

      sig { params(message: String).returns(Result) }
      def self.failure(message)
        new(success: false, integration: nil, message: message)
      end

      sig { returns(T::Boolean) }
      def success?
        success
      end
    end
  end
end
