# typed: strict
# frozen_string_literal: true

require_relative "context/default_context"
require_relative "context/null_context"

module GH
  # A collection of globally accessible data that is scoped to the current request or operation.
  # Unlike the legacy GitHub.context, this is not a hash and does not support arbitrary keys. All values are
  # typed and must be accessed via a method on the context object.
  module Context
    extend T::Helpers

    interface!

    CONTEXT_THREAD_KEY = :gh_context
    NULL_CONTEXT = T.let(NullContext.new.freeze, NullContext)

    # Returns the current context.
    sig { returns(Context) }
    def self.instance
      Thread.current[CONTEXT_THREAD_KEY] || NULL_CONTEXT
    end

    # This is the primary way to enable the context. It will yield the block with the context enabled and then
    # ensure that the context is disabled when the block exits.
    sig do
      type_parameters(:T).
      params(block: T.proc.returns(T.type_parameter(:T))).
      returns(T.type_parameter(:T))
    end
    def self.enabled(&block)
      current, previous = __init
      yield
    ensure
      __restore(previous) if previous
    end

    sig { returns(T::Boolean) }
    def self.enabled?
      Thread.current[CONTEXT_THREAD_KEY] != NULL_CONTEXT
    end

    # NEVER CALL THIS DIRECTLY IN PRODUCTION! Initializes a new context or returns the existing one if present.
    # This is only intended to be called in tests because they lack support for "around" blocks that
    # `enabled` requires.
    sig { returns([Context, Context]) }
    def self.__init
      previous = instance
      current = Thread.current[CONTEXT_THREAD_KEY] = DefaultContext.new
      [current, previous]
    end

    # NEVER CALL THIS DIRECTLY IN PRODUCTION! Restores the previous context and discards the current one.
    sig { params(ctx: Context).void }
    def self.__restore(ctx)
      Thread.current[CONTEXT_THREAD_KEY] = ctx
    end

    # NEVER CALL THIS DIRECTLY IN PRODUCTION! Resets the context to the null context.
    sig { void }
    def self.__reset
      Thread.current[CONTEXT_THREAD_KEY] = NULL_CONTEXT
    end

    # The identity context stack.
    sig { abstract.returns(GH::Auth::IdentityContext) }
    def identity_context; end

    # Access a consistent domain instance for a given identity and namespace.
    sig do
      abstract.params(
        namespace: Module,
        constructor: T.proc.returns(GH::Domain::Base)
      ).returns(GH::Domain::Base)
    end
    def domain(namespace, constructor); end
  end
end
