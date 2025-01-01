# typed: true
# frozen_string_literal: true

module Platform
  module Batch
    # GraphQLExecutor is a custom GraphQL Batch
    # executor tuned to GitHub's needs. It is used
    # to disable caching of batch loaders during mutations
    class GraphqlExecutor < GraphQL::Batch::Executor
      def initialize(*)
        super
        @reuse_loaders = true
      end

      def without_caching
        old_caching = @reuse_loaders
        @reuse_loaders = false
        yield
      ensure
        @reuse_loaders = old_caching
      end

      def resolve(loader)
        super
      ensure
        @loaders.delete(loader.loader_key) unless @reuse_loaders
      end
    end
  end
end
