# typed: strict
# frozen_string_literal: true

# This class exists to ensure that all iterations of an enumerable execute with the same GH::Context.
# Streamed responses are an example of an expected use of this class as the enumerator is iterated through
# after the response middleware tears down the request context.
module GH
  class ContextBoundEnumerator
    extend T::Generic
    Elem = type_member(:out)

    include Enumerable

    sig { params(args: T.untyped, block: T.untyped).void }
    def initialize(*args, &block)
      @identity_context = T.let(GH.context.identity_context, GH::Auth::IdentityContext)

      @enumerator = T.let(::Enumerator.new do |*args|
        GH::Context.enabled do
          T.cast(GH.context, GH::Context::DefaultContext).identity_context = @identity_context
          block.call(*args)
        end
      end, T::Enumerator[Elem])
    end

    sig do
      override.params(
        blk: T.proc.params(arg0: Elem).returns(BasicObject)
      )
      .returns(T.untyped)
    end
    def each(&blk)
      @enumerator.each(&blk)
    end
  end
end
