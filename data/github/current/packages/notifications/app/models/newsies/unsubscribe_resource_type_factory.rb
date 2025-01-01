# typed: true
# frozen_string_literal: true

module Newsies
  class UnsubscribeResourceTypeFactory
    class StandardResource
      def initialize(rollup_summary_result:)
        @rollup_summary_result = rollup_summary_result
        @thread_key = thread_key
      end

      def permalink
        rollup_summary_result.value&.thread&.permalink
      end

      def thread
        rollup_summary_result.value&.thread
      end

      def to_json
        rollup_summary_result.value&.to_json
      end

      def unsubscribe(user)
        Notifications::Subscriptions.unsubscribe_from_thread(user, thread)
      end

      def valid?
        thread.present?
      end

      private

      attr_reader :rollup_summary_result, :thread_key
    end

    class TransferableResource

      attr_reader :permalink, :thread

      def initialize(rollup_summary_result:, original_thread:)
        @rollup_summary_result = rollup_summary_result

        if rollup_summary_has_thread
          @thread = rollup_summary_result.value&.thread
          @permalink = rollup_summary_result.value&.thread&.permalink
        else
          thread = find_transfered_resource(original_thread)
          @thread = thread
          @permalink = thread&.permalink
        end
      end

      def rollup_summary_has_thread
        rollup_summary_result.value&.thread.present?
      end

      def to_json
        rollup_summary_result.value&.to_json
      end

      def find_transfered_resource(original_thread)
        transfer_klass = "#{original_thread.type}Transfer".constantize
        new_id = transfer_klass.find_new_id_by_original_id(original_id: original_thread.id)
        return nil if new_id.nil?
        original_thread.type.constantize.find_by(id: new_id)
      end

      def unsubscribe(user)
        Notifications::Subscriptions.unsubscribe_from_thread(user, thread)
      end

      def valid?
        thread.present?
      end

      private

      attr_reader :rollup_summary_result
    end

    def self.build(rollup_summary_result:, thread_key:)
      # Priortize rollup_summary thread key, but if we can't find any thread key exit early
      found_thread_key = rollup_summary_result.value&.thread_key || thread_key
      if found_thread_key.nil?
        return StandardResource.new(rollup_summary_result: rollup_summary_result)
      end

      original_thread = Thread.from_key(found_thread_key)
      if original_thread.type == "Issue" || original_thread.type == "Discussion"
        TransferableResource.new(rollup_summary_result: rollup_summary_result, original_thread: original_thread)
      else
        StandardResource.new(rollup_summary_result: rollup_summary_result)
      end
    end
  end
end
