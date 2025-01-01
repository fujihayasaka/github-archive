# typed: strict
# frozen_string_literal: true

module GitHub
  module Transitions
    module Iterators
      Identifier = T.type_alias { T.any(Numeric, String) }
      Identifiers = T.type_alias { T::Array[Identifier] }
      Items = T.type_alias { T::Hash[Identifier, T::Hash[Symbol, T.untyped]] }

      # Abstract base iterator class. Can be used to implement custom iterators
      # for one time use in a transition, or for reuse in many transitions.
      #
      # See `Iterators::DatabaseTable` for a reusable implementation.
      #
      # A minimal implementation has to implement a single method: `each_identifiers_batch`.
      # That method has to yield an `Array` of `Idenitfier` objects to a block.
      # Those objects are then passed to the `#build_items_for_batch` method of
      # for each batch. The return value of that method is then passed to the
      # transition via `#process_batch`. An example:
      #
      #    module GitHub::Transitions::Iterators
      #      class Example < Base
      #        def each_identifiers_batch(&block)
      #          # 1. read data, for instance based `arguments`
      #          # 2. yield identifiers in batches
      #          5.times do |index|
      #            yield [index]
      #          end
      #        end
      #
      #        def build_items_for_batch(identifiers)
      #          # convert array of identifiers to hash of items
      #          identifiers.each_with_object({}) do |i, hash|
      #            hash[i] = { foo: "bar" }
      #          end
      #        end
      #      end
      #    end
      #
      # The reason for the separation of identifiers and items is performance.
      # When using parallelization, it's important to to keep the data passed
      # from the main process to the worker processes as small as possible.
      # Benchmarks showed that passing an array of numeric values is around
      # 3x times faster than passing more complex data structures. Over hundreds
      # of thousand of batches, this sums up quickly into signficiant run time.
      #
      class Base
        extend T::Sig
        extend T::Helpers

        abstract!

        sig { returns(T.nilable(Transitions::Base)) }
        attr_accessor :transition

        sig { returns(Arguments) }
        attr_accessor :arguments

        sig { params(params: T::Hash[Symbol, T.untyped]).void }
        def initialize(params = {})
          @transition = T.let(nil, T.nilable(Transitions::Base))
          @arguments = T.let(Arguments.new, Arguments)
        end

        sig { overridable.void }
        def validate_arguments; end

        sig { overridable.void }
        def prepare_iteration; end

        sig { overridable.void }
        def prepare_worker; end

        sig do
          abstract.params(
            block: T.proc.params(items: Identifiers).void
          ).void
        end
        def each_identifiers_batch(&block); end

        sig { overridable.params(identifiers: Identifiers).returns(Items) }
        def build_items_for_batch(identifiers)
          Hash[identifiers.map { |i| [i, {}] }]
        end

        sig { overridable.returns(Integer) }
        def worker_count
          # no parallelization by default
          1
        end

        sig { params(message: String).void }
        def log(message)
          transition&.log(message)
        end

        sig { returns(T.nilable(T::Boolean)) }
        def dry_run?
          transition&.dry_run?
        end

        sig { returns(T.nilable(T::Boolean)) }
        def verbose?
          transition&.verbose?
        end
      end
    end
  end
end
