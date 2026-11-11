# typed: strict
# frozen_string_literal: true

module ActionsRules
  class EventActionWorkflowRun < T::Struct
    include Targeting::Targetable

    const :repository, Repository
    const :triggering_actor, User
    const :triggering_integration, T.nilable(IntegrationInstallation)
    const :event_name, String

    sig { override.returns(T::Hash[Targeting::Attribute, T.untyped]) }
    def targetable_attributes
      {}
    end

    sig { override.returns(Promise[T::Array[Targeting::Targetable]]) }
    def async_targetable_parents
      Promise.resolve(T.let([Targeting::Targets::Repository.new(repository:)], T::Array[Targeting::Targetable]))
    end
  end
end
