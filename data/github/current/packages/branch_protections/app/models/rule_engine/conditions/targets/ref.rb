# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Conditions
    # Helper to create a targetable object for a repository and ref_name
    class Targets::Ref

      include Targeting::Targetable

      sig do
        params(
          repository: Repository,
          ref_name: String
        ).void
      end
      def initialize(repository:, ref_name:)
        @repository = repository
        @ref_name = ref_name
      end

      sig { override.returns([Repository, String]) }
      def internal_record
        [@repository, @ref_name]
      end

      sig { override.returns(T::Hash[Targeting::Attribute, T.untyped]) }
      def targetable_attributes
        {
          Targeting::Attribute::RefName => @ref_name,
        }
      end

      sig { override.returns(Promise[T::Array[Targeting::Targetable]]) }
      def async_targetable_parents
        Promise.resolve(T.let([Targeting::Targets::Repository.new(repository: @repository)], T::Array[Targeting::Targetable]))
      end
    end
  end
end
