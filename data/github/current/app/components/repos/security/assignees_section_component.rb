# typed: strict
# frozen_string_literal: true

class Repos::Security::AssigneesSectionComponent < ApplicationComponent
  sig do
    params(
      repository: Repository,
      alert_number: Integer,
      current_user: T.untyped,
      assignees: T::Array[T.untyped],
      readonly: T::Boolean,
      system_arguments: T.untyped,
    ).void
  end
  def initialize(
    repository:,
    alert_number:,
    current_user:,
    assignees:,
    readonly:,
    **system_arguments
  )
    @repository = repository
    @alert_number = alert_number
    @current_user = current_user
    @assignees = assignees
    @readonly = readonly
    @system_arguments = T.let(system_arguments, T::Hash[Symbol, T.untyped])
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def assignees_section_props
    {
      alertNumber: @alert_number,
      repository: {
        name: @repository.name,
        ownerLogin: @repository.owner&.display_login,
      },
      currentUser: @current_user,
      assignees: @assignees,
      readonly: @readonly,
    }
  end
end
