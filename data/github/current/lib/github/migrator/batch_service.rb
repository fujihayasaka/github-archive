# typed: true
# frozen_string_literal: true

require "set"

module GitHub
  class Migrator
    class BatchService
      MAX_RETRIES = 5.freeze

      attr_reader :retry_exception_class

      def initialize(options = nil, &block)
        options = options || {}
        @block = block
        @retry_exception_class = options[:retry_on]
      end

      def add(thing)
        set_counter(batch.add(thing).size)

        if counter == batch_size
          call_with_retry { block.call(batch) }
          reset_batch
        end
      end

      def complete
        if batch.any?
          call_with_retry { block.call(batch) }
        end
        reset_batch
      end

      def batch_size
        GitHub.gh_migrator_batch_size
      end

      private

      attr_reader :block

      def batch
        @batch ||= Set.new
      end

      def counter
        @counter ||= 0
      end

      def set_counter(value)
        @counter = value
      end

      def reset_batch
        @counter = 0
        @batch = Set.new
      end

      # Retry 4 times
      def call_with_retry(retries = 1, &block)
        return block.call unless retry_exception_class
        begin
          block.call
        rescue retry_exception_class
          if retries < MAX_RETRIES
            sleep(2**retries + 3) if Rails.env.production?
            call_with_retry(retries + 1, &block)
          else
            raise
          end
        end
      end
    end
  end
end
