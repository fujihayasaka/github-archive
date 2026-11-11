# typed: true
# frozen_string_literal: true

module Billing
  module Stafftools
    class DeadLetterQueueDialogComponent < ApplicationComponent
      include GitHub::Memoizer

      def initialize(queue:, action:)
        @queue = queue
        @action = action
      end

      sig { returns(String) }
      def queue_name
        @queue[:queue]
      end

      sig { returns(Integer) }
      def queue_depth
        @queue[:depth].to_i
      end

      def form_url
        if @action == "clear"
          stafftools_billing_dead_letter_queue_do_clear_queue_path(queue: queue_name)
        elsif @action == "process"
          stafftools_billing_dead_letter_queue_do_process_queue_path(queue: queue_name)
        end
      end
    end
  end
end
