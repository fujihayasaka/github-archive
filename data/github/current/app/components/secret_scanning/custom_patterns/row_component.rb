# typed: true
# frozen_string_literal: true

module SecretScanning
  module CustomPatterns
    class RowComponent < ApplicationComponent
      attr_reader :pattern, :user_id, :unpublished, :push_protection_enabled, :show_path, :delete_path

      sig do
        params(
          pattern: T.any(GitHub::Proto::SecretScanning::Api::V3::SecretScanCustomPattern, GitHub::Proto::SecretScanning::Api::V2::SecretScanCustomPattern),
          user_id: T.nilable(Integer),
          unpublished: T::Boolean,
          show_path: String,
          delete_path: String,
          push_protection_enabled: T::Boolean,
        ).void
      end
      def initialize(pattern:, user_id:, unpublished:, show_path:, delete_path:, push_protection_enabled: false)
        @pattern = pattern
        @unpublished = unpublished
        @push_protection_enabled = push_protection_enabled
        @show_path = show_path
        @delete_path = delete_path
        @user_id = user_id
      end

      def pattern_state
        return :unpublished if unpublished
        :published
      end

      def user_can_edit_pattern?
        return true unless @pattern.scope == :business_scope
        @user_id == @pattern.created_by_id
      end
    end
  end
end
