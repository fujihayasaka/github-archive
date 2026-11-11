# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    # Walks a processor's precondition chain and memoizes cacheable gates so
    # the per-index processor fan-out from `Projects::DenormalizationProcessor`
    # shares one decision per `(gate.name, processor.class)` rather than
    # re-executing the gate's underlying work for each index.
    #
    # One evaluator lives per message; the orchestrator threads it into each
    # processor's `#consume(evaluator:)` call.
    #
    # Both successful boolean values and raised exceptions are cached and
    # replayed.
    class PreconditionEvaluator
      # Outcome of evaluating a precondition chain. `reason` holds the
      # `FailureReason` constant when the chain failed, `nil` otherwise.
      class Decision < T::Struct
        const :allowed, T::Boolean
        const :reason, T.nilable(String), default: nil

        sig { returns(T::Boolean) }
        def allowed?
          allowed
        end
      end

      # One step in a precondition chain. `name` is the cache key, `allowed`
      # is the lambda invoked to decide pass/fail, and `failure_reason` is
      # carried in the `Decision` when the gate blocks the chain.
      class Gate < T::Struct
        const :name, Symbol
        const :allowed, T.proc.returns(T::Boolean)
        const :failure_reason, String
        const :cacheable, T.nilable(T::Boolean)
      end

      # Recorded outcome of one gate execution. Holds either a boolean or an
      # exception; `replay!` returns the value or re-raises.
      class CachedOutcome < T::Struct
        const :value, T.nilable(T::Boolean), default: nil
        const :error, T.nilable(StandardError), default: nil

        sig { returns(T::Boolean) }
        def replay!
          if (e = error)
            raise e
          end

          T.must(value)
        end
      end

      CACHE_HIT_METRIC = T.let("memex.indexable.gate.cache_hit", String)

      ALLOWED = T.let(Decision.new(allowed: true).freeze, Decision)

      sig { params(message: GitHub::StreamProcessors::Message).void }
      def initialize(message)
        @message = message
        @cache = T.let(
          {},
          T::Hash[Symbol, T::Hash[T.class_of(Base), CachedOutcome]],
        )
      end

      # Walks the supplied processor's gates in order, returning the first
      # failing gate's `Decision` (or `ALLOWED` if every gate passes).
      # Cacheable gates are memoized per `(gate.name, processor.class)` so a
      # second processor that hits the same gate for the same message
      # replays the prior outcome — including any cached exception —
      # instead of re-executing the lambda.
      #
      # Raises `ArgumentError` if `processor.message` is not the message
      # this evaluator was constructed for.
      sig { params(processor: Base).returns(Decision) }
      def run(processor:)
        unless processor.message.equal?(@message)
          raise ArgumentError,
            "Cannot run PreconditionEvaluator: its cached message is not the same object as processor.message. " \
            "Construct a fresh evaluator per message, then reuse it across the per-index processor fan-out for that message."
        end

        processor.precondition_gates.each do |gate|
          next if evaluate(gate, processor:)

          return Decision.new(allowed: false, reason: gate.failure_reason)
        end

        ALLOWED
      end

      # Returns the gate's pass/fail signal (true = pass).
      #
      # Cacheable gates record their outcome under `(gate.name,
      # processor.class)` and replay it on subsequent calls. Non-cacheable
      # gates always invoke `gate.allowed` and never touch the cache —
      # currently only `_matching_elasticsearch_documents?`, whose per-index
      # Elasticsearch state is what's being checked.
      #
      # Emits `CACHE_HIT_METRIC` on every cache hit.
      sig { params(gate: Gate, processor: Base).returns(T::Boolean) }
      private def evaluate(gate, processor:)
        if gate.cacheable && (cached = cache_for(gate)[processor.class])
          GitHub.dogstats.increment(CACHE_HIT_METRIC, tags: cache_hit_tags(gate, processor))
          return cached.replay!
        end

        outcome =
          begin
            CachedOutcome.new(value: gate.allowed.call)
          rescue StandardError => e
            cache_for(gate)[processor.class] = CachedOutcome.new(error: e) if gate.cacheable
            raise
          end

        cache_for(gate)[processor.class] = outcome if gate.cacheable
        outcome.replay!
      end

      sig { params(gate: Gate).returns(T::Hash[T.class_of(Base), CachedOutcome]) }
      private def cache_for(gate)
        @cache[gate.name] ||= {}
      end

      # Builds a Gate that passes when `predicate` returns truthy.
      sig { params(predicate: Method, failure_reason: String, cacheable: T::Boolean).returns(Gate) }
      def self.truthy_gate(predicate:, failure_reason:, cacheable: false)
        Gate.new(
          name: predicate.name,
          allowed: -> { predicate.call },
          failure_reason:,
          cacheable:,
        )
      end

      # Builds a Gate that passes when `predicate` returns falsy (i.e. the
      # predicate names the failure condition).
      sig { params(predicate: Method, failure_reason: String, cacheable: T::Boolean).returns(Gate) }
      def self.falsy_gate(predicate:, failure_reason:, cacheable: false)
        Gate.new(
          name: predicate.name,
          allowed: -> { !predicate.call },
          failure_reason:,
          cacheable:,
        )
      end

      sig { params(gate: Gate, processor: Base).returns(T::Array[String]) }
      private def cache_hit_tags(gate, processor)
        [
          "gate:#{gate.name}",
          "processor:#{processor.class.name}",
          "index:#{processor.index.name}",
        ]
      end
    end
  end
end
