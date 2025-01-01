# typed: true
# frozen_string_literal: true

module Billing
  module Notifications
    class Result
      attr_reader :value, :threshold, :tags, :context

      def initialize(value:, threshold:, tags:, context: nil)
        @value = value
        @threshold = threshold
        @tags = tags
        @context = context
      end
    end
  end
end
