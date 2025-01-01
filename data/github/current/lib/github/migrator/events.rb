# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    module Events
      # Public: Register or retrieve the event handlers for progress_with_count
      # events.
      #
      # block - A callback that will be called when progress_with_count occurs.
      #
      # Example:
      #
      #   obj.on_progress_with_count do |count|
      #     increment_and_print_records_added("export", count)
      #   end
      def on_progress_with_count(&block)
        event_accessor(:progress_with_count, &block)
      end

      # Public: Register or retrieve the event handlers for
      # sample_resource_usage events.
      #
      # block - A callback that will be called when sample_resource_usage occurs.
      #
      # Example:
      #
      #   obj.on_sample_resource_usage do
      #     record_memory_usage
      #   end
      def on_sample_resource_usage(&block)
        event_accessor(:sample_resource_usage, &block)
      end

      def fire(name, *args)
        event_accessor(name).call(*args)
      end

      private

      def event_accessor(name, &block)
        @events ||= Hash.new { |h, k| h[k] = EventHandlers.new }
        @events[name] << block if block
        @events[name]
      end

      class EventHandlers < Array
        def call(*args)
          each do |block|
            block.call(*args)
          end
        end
      end

      class Null
        include Events
      end
    end
  end
end
