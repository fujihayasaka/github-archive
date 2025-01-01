# typed: true
# frozen_string_literal: true

# Resilient::CircuitBreaker::ActiveTracker
# This is a per-thread singleton class, i.e. each thread only has one instance
# It tracks which Resilient::CircuitBreakers are currently active,
#    * active means a circuit-breaker had `.allow_request?` called on it, which means there is currently a resource
#      that is doing ~something~ that it deems needs to be behind a circuit-breker,
#      e.g. talking to the DB, talking to 3rd party APIs
#
#      a circuit-breaker is marked inactive (i.e. no longer tracked) when it has one of `.success` or `.failure` called
#      on it,
#      this is because the circuit-broken resource has gotten a response from whatever it is doing,
#      regardless if the response is a failure or a success, we are not waiting on this resource anymore and the
#      circuit-breaker is not active
module Resilient
  class CircuitBreaker
    class ActiveTracker
      extend T::Helpers
      extend T::Sig

      # class-method, returns singleton instance of Resilient::CircuitBreaker::ActiveTracker on a per-thread basis
      def self.instance
        Thread.current[:resilient_circuit_breaker_active_tracker] ||= new
      end

      private_class_method(:new)

      # returns array of active_circuit_breakers for a given thread
      sig { params(thread: Thread).returns(T::Array[String]) }
      def self.active_circuit_breakers(thread)
        thread[:resilient_circuit_breaker_active_tracker]&.active_circuit_breakers || []
      end

      # constructor for Resilient::CircuitBreaker::ActiveTracker, creates instance-variable hash that keeps track of
      # circuit_breaker keys and how many times they have been 'triggered' in process
      sig { void }
      def initialize
        @active_circuit_breakers = T.let(Hash.new(0), T::Hash[String, Integer])
      end

      # returns array of circuit_breaker names that currently have requests in flight
      sig { returns(T::Array[String]) }
      def active_circuit_breakers
        @active_circuit_breakers.keys
      end

      # this method takes a `key` string parameter, the name of the circuit-breaker that we want to track
      # it stores the name of the circuit-breaker, alongside the number of times it has been used in the current
      # call-path
      sig { params(key: String).void }
      def increment_circuit_breaker(key)
        # this is to satisfy sorbet, need to let it know that hash[key] is indeed an integer
        val = @active_circuit_breakers[key].to_i

        @active_circuit_breakers[key] = val + 1

        nil
      end

      # this method takes a `key` string parameter, the name of the circuit-breaker that we want to track
      # it decrements the number of times a circuit-breaker is in use, if the circuit-breaker is no longer in use
      # it deletes it entirely
      sig { params(key: String).void }
      def decrement_active_circuit_breaker(key)
        # this is to satisfy sorbet, need to let it know that hash[key] is indeed an integer
        old_val = @active_circuit_breakers[key].to_i
        new_val = old_val - 1

        if new_val.positive?
          @active_circuit_breakers[key] = new_val
        else
          @active_circuit_breakers.delete(key)
        end

        nil
      end

      # this resets the circuit-breaker tracker, useful for tests
      sig { void }
      def clear
        @active_circuit_breakers.clear

        nil
      end
    end
  end
end
