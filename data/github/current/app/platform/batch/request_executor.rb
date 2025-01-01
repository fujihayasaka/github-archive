# typed: true
# frozen_string_literal: true

module Platform
  module Batch
    # RequestExecutor is a custom GraphQL Batch
    # executor which behaves like older GraphQL::Batch
    # versions by deleting loaders after they have been resolved.
    class RequestExecutor < GraphQL::Batch::Executor
      def resolve(loader)
        super
      ensure
        @loaders.delete(loader.loader_key)
      end
    end
  end
end
