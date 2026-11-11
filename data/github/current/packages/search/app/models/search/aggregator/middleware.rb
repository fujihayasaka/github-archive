# typed: true
# frozen_string_literal: true

module Search
  class Aggregator
    class Middleware

      def initialize(app)
        @app = app
      end

      def call(env)
        aggregator = Search::Aggregator.instance
        aggregator.reset # Ensure no data from a previous failed request
        aggregator.aggregate do
          @app.call(env)
        end
      ensure
        push_indexes_events(aggregator)
      end

      def push_indexes_events(aggregator)
        aggregator.rollup do |job, args, options, replication_state|
          DatabaseSelector::LastOperations.with_static_replication_state(replication_state) do
            job.set(options).perform_later(*args)
          end
        end
      end
    end
  end
end
