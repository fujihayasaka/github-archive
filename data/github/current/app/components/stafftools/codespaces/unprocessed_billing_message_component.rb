# typed: true
# frozen_string_literal: true

module Stafftools
  module Codespaces
    class UnprocessedBillingMessageComponent < ApplicationComponent
      attr_reader :message

      delegate :body, :message_id, :azure_storage_account_name, to: :message

      def initialize(message:)
        @message = message
      end

      def tidy_json_body
        return "The message body is empty" if body.empty?
        prettified = JSON.pretty_generate(JSON.parse(body))
        GitHub::Colorize.highlight_json(prettified)
      end
    end
  end
end
