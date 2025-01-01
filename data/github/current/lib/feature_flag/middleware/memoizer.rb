# typed: strict
# frozen_string_literal: true

module FeatureFlag
  module Middleware
    class Memoizer
      extend T::Helpers

      MEMOIZE_TTL = T.let(5.seconds, Numeric)

      sig { params(app: T.untyped).void }
      def initialize(app)
        @app = T.let(app, T.untyped)
      end

      sig { params(env: T::Hash[T.any(String, Symbol), T.untyped]).returns(T::Array[T.untyped]) }
      def call(env)
        if Thread.current[:vexi_memoize_start_time].nil? || !FeatureFlag.vexi.memoizing? || Time.now - Thread.current[:vexi_memoize_start_time] > MEMOIZE_TTL
          FeatureFlag.vexi.memoize = true
          Thread.current[:vexi_memoize_start_time] = Time.now
        end

        @app.call(env)
      ensure
        if Thread.current[:vexi_memoize_start_time].nil? || Time.now - Thread.current[:vexi_memoize_start_time] > MEMOIZE_TTL
          FeatureFlag.vexi.memoize = false
          Thread.current[:vexi_memoize_start_time] = nil
        end
      end
    end
  end
end
