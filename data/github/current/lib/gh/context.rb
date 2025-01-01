# typed: strict
# frozen_string_literal: true

require_relative "context/default_context"
require_relative "context/null_context"
require_relative "context/stack"

module GH
  # A collection of globally accessible data that is scoped to the current request or operation.
  # Unlike the legacy GitHub.context, this is not a hash and does not support arbitrary keys. All values are
  # typed and must be accessed via a method on the context object.
  module Context
    extend T::Helpers

    interface!

    CONTEXT_THREAD_KEY = :gh_context
    NULL_CONTEXT = T.let(NullContext.new.freeze, NullContext)

    sig { returns(Stack[Context]) }
    def self.stack
      Thread.current[CONTEXT_THREAD_KEY] ||= Stack.new(NULL_CONTEXT)
    end
    private_class_method :stack

    # Returns the current context.
    sig { returns(Context) }
    def self.instance
      T.must(stack.peek)
    end

    # This is the primary way to enable the context. It will yield the block with the context enabled and then
    # ensure that the context is disabled when the block exits.
    sig do
      type_parameters(:T).
      params(block: T.proc.returns(T.type_parameter(:T))).
      returns(T.type_parameter(:T))
    end
    def self.enabled(&block)
      __init
      yield
    ensure
      stack.pop
    end

    sig { returns(T::Boolean) }
    def self.enabled?
      instance != NULL_CONTEXT
    end

    # NEVER CALL THIS DIRECTLY IN PRODUCTION! Initializes a new context or returns the existing one if present.
    # This is only intended to be called in tests because they lack support for "around" blocks that
    # `enabled` requires.
    sig { returns([Context, T.nilable(Context)]) }
    def self.__init
      previous = stack.peek
      stack.push(DefaultContext.new)
      [instance, previous]
    end

    # NEVER CALL THIS DIRECTLY IN PRODUCTION! Restores the previous context and discards the current one.
    sig { void }
    def self.__restore
      raise "Attempting to pop NULL_CONTEXT" if stack.peek == NULL_CONTEXT
      stack.pop
    end

    # NEVER CALL THIS DIRECTLY IN PRODUCTION! Resets the context to the null context.
    sig { void }
    def self.__reset
      Thread.current[CONTEXT_THREAD_KEY] = Stack.new(NULL_CONTEXT)
    end

    # The current identity context.
    sig { abstract.returns(GH::Auth::IdentityContext) }
    def identity_context; end

    # Set the identity context.
    sig { abstract.params(ctx: GH::Auth::IdentityContext).void }
    def identity_context=(ctx); end

    # Shorthand to set a new identity context for the duration of the optional block.
    sig { abstract.params(actor: T.nilable(GH::Auth::Actor), blk: T.nilable(T.proc.void)).void }
    def act_as(actor, &blk); end

    # Access a consistent domain instance for a given identity and namespace.
    sig do
      abstract.params(
        namespace: Module,
        constructor: T.proc.returns(GH::Domain::Base)
      ).returns(GH::Domain::Base)
    end
    def domain(namespace, constructor); end

    sig { abstract.params(namespace: Module).returns(T::Array[GH::Domain::Base]) }
    def all_domains_for(namespace); end

    private

    sig { abstract.returns(T::Hash[String, T::Hash[Module, GH::Domain::Base]]) }
    def domain_map; end
  end
end
