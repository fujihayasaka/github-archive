# typed: true
# frozen_string_literal: true

module Site
  module Header
    class UserStatusItemComponent < ApplicationComponent
      attr_reader :user_status

      def initialize(user_status:, **system_arguments)
        @user_status = user_status
      end

      def emoji
        return nil unless user_status&.emoji
        @emoji ||= Emoji.find_by_alias(user_status.emoji.gsub(":", ""))
      end
    end
  end
end
