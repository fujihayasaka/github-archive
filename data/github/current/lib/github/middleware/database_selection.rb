# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    # When enabled, this middleware determines whether a request should be
    # routed to the primary or the replica.
    #
    # If a request is a writing HTTP verb like PUT, PATCH, etc the request
    # will be automatically routed to a primary (write) database.
    #
    # If a request is a GET or HEAD request the DatabaseSelector will do a
    # calculation whether it's safe to send the request to a read from a
    # replica. Safety is determined by whether the replicas are up to date.
    #
    # For write requests we set a "last write timestamp" so that future
    # requests for that user know to go to a primary if the "last read
    # timestamp" wasn't updated after.
    #
    # The GitHub app guarantees "read your own write" but does not
    # guarantee other users will be sent to a primary after you write.
    # This means there may be a short delay between you reading your own
    # write and another user reading your write. Unless there is severe
    # replica lag, the GitHub app guarantees other users will be able
    # to read your write in less than 5 seconds.

    REPLICA_PATHS = %w(/_alive).freeze
    private_constant :REPLICA_PATHS

    class DatabaseSelection
      def initialize(app)
        @app = app
      end

      def call(env)
        request = ActionDispatch::Request.new(env)

        select_database(request) do
          @app.call(env)
        end
      end

      private

      def select_database(request, &bk)
        last_operations = ::DatabaseSelector::LastOperations.from_session(request.session)
        if read_request?(request)
          ::DatabaseSelector.instance.read_from_database(last_operations: last_operations, called_from: :middleware, &bk)
        else
          ::DatabaseSelector.instance.track_writes(last_operations) do
            ActiveRecord::Base.connected_to(role: :writing, &bk)
          end
        end
      end

      def read_request?(request)
        request.get? || request.head? || read_url?(request)
      end

      def read_url?(request)
        REPLICA_PATHS.include?(request.path_info)
      end
    end
  end
end
