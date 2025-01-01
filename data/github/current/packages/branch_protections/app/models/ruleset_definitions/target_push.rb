# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  module TargetPush

    sig { returns(T::Array[String]) }
    def target_required_condition_targets
      []
    end

    class RepositoryOverride
      attr_reader :repository

      def initialize(repository)
        @repository = repository
      end

      sig { returns(T.nilable(Organization)) }
      def organization
        repository.owner if repository.owner.is_a?(Organization)
      end
    end

    sig do
      params(targetable: RuleEngine::Conditions::Targetable)
      .returns(RuleEngine::Conditions::Targetable)
    end
    def redirect_condition_targetable(targetable)
      if targetable.repository&.fork?
        # redirect to the network root
        RuleEngine::Conditions::ConditionOverride.new([RepositoryOverride.new(targetable.repository&.network&.root)], targetable)
      else
        targetable
      end
    end
  end
end
