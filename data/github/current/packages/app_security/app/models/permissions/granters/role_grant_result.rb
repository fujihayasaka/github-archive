# typed: true
# frozen_string_literal: true

module Permissions
  module Granters
    class RoleGrantResult
      attr_reader :reason, :success

      def initialize(reason: nil, success:)
        @reason = reason
        @success = success
      end

      def self.failure!(reason:)
        new(reason: reason, success: false)
      end

      def self.success!
        new(success: true)
      end

      def success?
        success
      end
    end
  end
end
