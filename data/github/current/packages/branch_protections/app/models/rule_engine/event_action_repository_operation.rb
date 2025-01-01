# typed: strict
# frozen_string_literal: true

module RuleEngine
  class EventActionRepositoryOperation < ApplicationRecord::Repositories
    extend T::Helpers

    include Conditions::Targetable

    SUPPORTED_OPERATIONS = T.let([:create, :rename, :delete, :transfer, :change_visibility], T::Array[Symbol])
    POST_APPROVAL_ACTIONS = T.let([:delete, :change_visibility], T::Array[Symbol])

    include ::Repositories::BelongsToRepository
    flagged_belongs_to_repository_via_domain
    has_one :rule_suite, class_name: "RuleEngine::RuleSuite", dependent: :destroy, foreign_key: "event_action_id", inverse_of: :event_action

    validates :repository_id, presence: true
    validates :operation, presence: true
    validate :operation_is_valid

    sig { returns(T.nilable(T::Hash[String, T.untyped])) }
    attr_accessor :repo_create_custom_properties

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
      async_repository.then do |repository|
        next nil if repository.nil?
        Conditions::Targets::Repository.new(repository: repository, repo_create_custom_properties:)
      end
    end
  end
end
