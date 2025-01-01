# typed: true
# frozen_string_literal: true

module Billing
  module Notifications
    class EvaluationCase
      attr_reader :tags, :proc

      def initialize(tags:, proc:)
        @tags = tags
        @proc = proc
      end

      def includes_tags?(interesting_tags)
        (tags & Array(interesting_tags)).present?
      end
    end
  end
end
