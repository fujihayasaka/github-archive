# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Conditions
    # Helper to create a targetable object for a repository and ref_name
    class Targets::Ref

      include Targetable

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

      sig { override.returns(T::Hash[RuleEngine::Conditions::Targetable::Attribute, T.untyped]) }
      def targetable_attributes
        {
          Attribute::RefName => @ref_name,
        }
      end

      sig { override.returns(Promise[T.nilable(RuleEngine::Conditions::Targetable)]) }
      def async_targetable_parent
        T.cast(Promise.resolve(RuleEngine::Conditions::Targets::Repository.new(repository: @repository)), Promise[T.nilable(RuleEngine::Conditions::Targetable)])
      end
    end
  end
end
