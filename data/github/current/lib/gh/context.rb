# typed: strict
# frozen_string_literal: true

require_relative "context/scoped_data"
require_relative "context/owner_context"
require_relative "context/null_owner_context"
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
      # Call on_context_exit for all scoped data before popping.
      # Rescue errors to ensure stack.pop always runs and one failing handler
      # doesn't prevent others from running.
      # Iterate a snapshot so handlers can safely mutate data during teardown.
      instance.data.to_a.each do |key, scoped_data|
        scoped_data.on_context_exit
      rescue => e
        Failbot.report(e, context: "ScopedData#on_context_exit failed for :#{key}")
      end
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
        namespace: T::Module[T.anything],
        constructor: T.proc.returns(GH::Domain::Base)
      ).returns(GH::Domain::Base)
    end
    def domain(namespace, constructor); end

    sig { abstract.params(namespace: T::Module[T.anything]).returns(T::Array[GH::Domain::Base]) }
    def all_domains_for(namespace); end

    # Returns a registry of local remote cache stores
    sig { abstract.returns(T.nilable(Concurrent::Hash)) }
    def remote_cache_registry; end

    # The current owner context for shard boundary detection.
    sig { abstract.returns(OwnerContext) }
    def owner; end

    sig { abstract.returns(GitHub::RemoteCacheOverride) }
    def remote_cache_override; end

    sig { abstract.params(value: GitHub::RemoteCacheOverride).void }
    def remote_cache_override=(value); end

    # Request-scoped data storage for domain code.
    # Data objects must implement ScopedData interface.
    # Their on_context_exit method is called when the context is popped.
    sig { abstract.returns(T::Hash[Symbol, ScopedData]) }
    def data; end

    private

    sig { abstract.returns(T::Hash[String, T::Hash[T::Module[T.anything], GH::Domain::Base]]) }
    def domain_map; end
  end
end
