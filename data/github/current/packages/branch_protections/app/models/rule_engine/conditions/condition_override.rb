# typed: true
# frozen_string_literal: true

module RuleEngine
  module Conditions
    # A helper class to faciliate overriding part of a Targetable object
    class ConditionOverride
      extend T::Sig
      include Targetable

      sig { returns(Targetable) }
      attr_reader :fallback

      sig { returns(T::Array[T.untyped]) }
      attr_reader :overrides

      # Takes in a list of overrides and a fallback targetable object
      # The overrides should implement part of Targetable
      sig { params(overrides: T::Array[T.untyped], fallback: Targetable).void }
      def initialize(overrides, fallback)
        @overrides = overrides
        @fallback = fallback
      end

      sig { override.returns(T.nilable(Organization)) }
      def organization
        override = @overrides.find { |o| o.respond_to?(:organization) }
        override ? override.organization : fallback.organization
      end

      sig { override.returns(T.nilable(Repository)) }
      def repository
        override = @overrides.find { |o| o.respond_to?(:repository) }
        override ? override.repository : fallback.repository
      end

      sig { override.returns(T.nilable(String)) }
      def ref_name
        override = @overrides.find { |o| o.respond_to?(:ref_name) }
        override ? override.ref_name : fallback.ref_name
      end
    end
  end
end
