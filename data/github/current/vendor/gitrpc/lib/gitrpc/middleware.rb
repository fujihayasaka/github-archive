# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

require "gitrpc/middleware/instrumentation"
require "gitrpc/middleware/ensure_valid_call"

module GitRPC
  class Middleware

    def initialize(backend, &blk)
      @backend = backend
      @use = []
      instance_eval(&blk) if block_given?
    end

    def use(middleware)
      @use << middleware
    end

    def stack
      @use.reverse.inject(@backend) do |backend, middleware|
        middleware.new(backend)
      end
    end

    def method_missing(meth, *args, **kwargs, &blk)
      super unless @backend.respond_to?(meth)

      stack.call(meth, *args, **kwargs)
    end

    # FIXME: this should probably be respond_to_missing?
    def respond_to?(name, include_private = false)
      @backend.respond_to?(name)
    end
  end
end
