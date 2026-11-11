# typed: true
# frozen_string_literal: true

# BERTRPC::MuxHandler implements something almost identical to what we need here.
# We reuse the BERTRPC::MuxHandler::CallState part, and reimplement the select loop
# bit to let IOPromise's core loop handle the IO.select.

require "iopromise"

module IOPromise
  module BERTRPC
    class ExecutorPool < IOPromise::ExecutorPool::Base
      def execute_continue
        timeouts = []
        finished = []

        @pending.each do |item|
          unless item.started_executing?
            # instrumentation hook, note that we are starting execution
            begin_executing(item)

            # we can immediately start running the BERTRPC call.
            # pass the promise as the mod_obj so it's passed to mux calls,
            # and send this executor as the mux_handler.
            item.bert_action.execute(item, self)

            # we also need to tell the call state to do the first "pass" through.
            # this follows what BERTRPC::MuxHandler does
            item.monitor_ready(nil, nil)
          end

          item.update_monitor

          if item.bert_call_state.finished?
            # notify instrumentation that the RPC has finished, queue up resolving promises
            item.safe_pass_result
            finished << item
            next
          end

          if item.timeout? || !item.bert_call_state.error.nil?
            # we processed everything we had, but didn't complete before the timeout,
            # or we hit an error in processing a socket function.
            item.safe_pass_result
            finished << item
            next
          end

          timeouts << item.timeout_remaining
        end

        # finally, complete any callbacks (this is done once we've notified all instrumenters)
        finished.each { |item| finalise_and_callback(item) }

        # find the shortest non-nil timeout, or if all timeouts are nil then nil (no timeout)
        self.select_timeout = timeouts.compact.min
      end

      def finalise_and_callback(item)
        call = item.bert_call_state

        call.call_callbacks
        call.cleanup
      end

      # mux_handler
      def connect(item, host, port)
        item.bert_call_state.connect(host, port)
      end

      # mux_handler
      def write(item, data)
        item.bert_call_state.write(data)
      end
    end
  end
end
