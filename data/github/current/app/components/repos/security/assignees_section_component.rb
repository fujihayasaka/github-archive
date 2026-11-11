# typed: strict
# frozen_string_literal: true

class Repos::Security::AssigneesSectionComponent < ApplicationComponent
  sig do
    params(
      type: Symbol,
      repository: Repository,
      alert_number: Integer,
      current_user: T.untyped,
      assignees: T::Array[T.untyped],
      readonly: T::Boolean,
      assignable_to_copilot: T::Boolean,
      use_copilot_assignment_modal: T::Boolean,
      use_agentic_autofix: T::Boolean,
      has_valid_suggested_fix: T.nilable(T::Boolean),
      suggested_fix_alive_channel: T.nilable(String),
      system_arguments: T.untyped,
    ).void
  end
  def initialize(
    type:,
    repository:,
    alert_number:,
    current_user:,
    assignees:,
    readonly:,
    assignable_to_copilot:,
    use_copilot_assignment_modal: false,
    use_agentic_autofix: false,
    has_valid_suggested_fix: nil,
    suggested_fix_alive_channel: nil,
    **system_arguments
  )
    @type = type
    @repository = repository
    @alert_number = alert_number
    @current_user = current_user
    @assignees = assignees
    @readonly = readonly
    @assignable_to_copilot = assignable_to_copilot
    @use_copilot_assignment_modal = use_copilot_assignment_modal
    @use_agentic_autofix = use_agentic_autofix
    @has_valid_suggested_fix = has_valid_suggested_fix
    @suggested_fix_alive_channel = suggested_fix_alive_channel
    @system_arguments = T.let(system_arguments, T::Hash[Symbol, T.untyped])
  end

  TYPE_TO_PARTIAL_PREFIX = T.let({
    dependabot: "dependabot-alert",
  }.freeze, T::Hash[Symbol, String])

  sig { returns(String) }
  def react_partial_name
    "#{TYPE_TO_PARTIAL_PREFIX.fetch(@type)}-assignees-section"
  end

  sig { returns(String) }
  def test_selector_name
    "#{TYPE_TO_PARTIAL_PREFIX.fetch(@type)}-assignees-section"
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
      assignableToCopilot: @assignable_to_copilot,
      useCopilotAssignmentModal: @use_copilot_assignment_modal,
      useAgenticAutofix: @use_agentic_autofix,
      hasValidSuggestedFix: @has_valid_suggested_fix,
      suggestedFixAliveChannel: @suggested_fix_alive_channel,
    }
  end
end
