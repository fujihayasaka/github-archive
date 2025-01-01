# typed: strict
# frozen_string_literal: true

module RuleEngine
  class EventActionRepositoryOperation < ApplicationRecord::Domain::RuleInsights
    extend T::Helpers

    include ApplicationRecord::Sharding
    configure_sharding(sharding_key: :repository_id, should_shard: -> (_, _) { true })

    include Conditions::Targetable

    SUPPORTED_OPERATIONS = T.let([:create, :rename, :delete, :transfer, :change_visibility], T::Array[Symbol])
    POST_APPROVAL_ACTIONS = T.let([:delete, :change_visibility], T::Array[Symbol])

    include ::Repositories::BelongsToRepository
    belongs_to_repository_via_domain
    has_one :rule_suite, ->(event_action) { where(repository_id: event_action.repository_id) },
      class_name: "RuleEngine::RuleSuite", dependent: :destroy, foreign_key: "event_action_id", inverse_of: :event_action

    validates :repository_id, presence: true
    validates :operation, presence: true
    validate :operation_is_valid

    sig { returns(Promise[T.nilable(Events::RepositoryOperationEvent::RepositoryModel)]) }
    def async_repository_model
      promise = if @repository_model
        Promise.resolve(@repository_model)
      else
        async_repository
      end
      T.cast(promise, Promise[T.nilable(Events::RepositoryOperationEvent::RepositoryModel)])
    end

    sig { params(repository_model: T.nilable(Events::RepositoryOperationEvent::RepositoryModel)).void }
    def repository_model=(repository_model)
      @repository_model = T.let(repository_model, T.nilable(Events::RepositoryOperationEvent::RepositoryModel))
      if repository_model.is_a?(Repository)
        self.repository = repository_model
      end
    end

    sig { returns(Symbol) }
    def operation
      read_attribute(:operation).to_sym
    end

    sig { returns(T::Boolean) }
    def post_approval_action?
      POST_APPROVAL_ACTIONS.include?(operation)
    end

    sig { void }
    def operation_is_valid
      errors.add("Unsupported repository operation #{operation}") unless SUPPORTED_OPERATIONS.include?(operation)
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def json_payload
      {
        repository_id: repository_id,
        operation: operation,
        operation_value: operation_value,
      }
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def instrument_data
      json_payload
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def evaluation_data
      json_payload
    end

    sig { override.returns(T::Hash[RuleEngine::Conditions::Targetable::Attribute, T.untyped]) }
    def targetable_attributes
      {}
    end

    sig { override.returns(Promise[T.nilable(RuleEngine::Conditions::Targetable)]) }
    def async_targetable_parent
      async_repository_model.then do |repository|
        next nil if repository.nil?
        if repository.is_a?(Repository)
          Conditions::Targets::Repository.new(repository:)
        else
          repository
        end
      end
    end
  end
end
