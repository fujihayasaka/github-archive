# typed: true
# frozen_string_literal: true

# This middleware is responsible for resetting GraphQL::Batch's thread-local
# state between requests. Without this middleware the app would share loaded
# objects between requests which could cause us to leak private data, serve
# stale data, or leak memory.
#
module Platform
  module Middleware
    class BatchLoading
      def initialize(app)
        @app = app
      end

      def call(env)
        GraphQL::Batch::Executor.end_batch
        @app.call(env)
      end
    end
  end
end
