# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module GitHub
  module Exceptions
    # BasicRollup responds to `failbot_rollup` which our failbot configuration uses to
    # determine the fingerprint used by Sentry issue grouping. This rollup differs from
    # the default roller by not including the backtrace in the fingerprint. Instead, it
    # uses the exception class.
    module BasicRollup
      extend T::Sig
      extend T::Helpers

      @_rollup_classes = T.let(Set.new, T::Set[T.class_of(Exception)])

      sig { params(exception: Exception).returns(T::Boolean) }
      def self.should_rollup?(exception)
        rollup_classes.any? { |cls| exception.is_a?(cls) }
      end

      sig { params(exception: Exception, context: T::Hash[String, String]).returns(String) }
      def self.rollup(exception, context)
        Digest::SHA256.hexdigest(exception.class.name.to_s)
      end

      sig { returns(T::Set[T.class_of(Exception)]) }
      def self.rollup_classes
        @_rollup_classes
      end
    end
  end
end
