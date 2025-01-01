# typed: true
# frozen_string_literal: true

module Newsies
  module Responses
    class Settings < Newsies::Response
      def initialize(&block)
        super(Newsies::Settings.new)
      end

      def platform_type_name
        "NotificationSettings"
      end
    end
  end
end
