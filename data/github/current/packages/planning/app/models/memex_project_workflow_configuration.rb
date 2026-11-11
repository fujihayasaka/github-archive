# typed: true
# frozen_string_literal: true

class MemexProjectWorkflowConfiguration
  # Trigger types whose default workflow exposes a recommended status option (sourced
  # from the in-memory `default_workflow_attributes` hash that this class is initialized
  # with — specifically its `get_project_items.fieldOptionId`). Today only the
  # auto-assign-agent workflow surfaces a recommendation.
  TRIGGER_TYPES_WITH_RECOMMENDED_FIELD_OPTION = T.let(
    [:auto_assign_agent].freeze,
    T::Array[Symbol],
  )

  attr_reader :default_workflow, :enableable, :constraints, :trigger_type, :recommended_field_option_id

  def initialize(default_workflow_attributes:, actor:)
    @default_workflow = MemexProjectWorkflow.new(default_workflow_attributes)
    @trigger_type = default_workflow_attributes[:trigger_type]
    @enableable = MemexProjectWorkflow.trigger_type_is_enableable(@trigger_type, actor)
    @constraints = {
      "contentTypes": MemexProjectWorkflow.get_valid_content_types_for_trigger_type(@trigger_type)
    }
    @recommended_field_option_id = extract_recommended_field_option_id(default_workflow_attributes)
  end

  def to_hash
    hash = {
      triggerType: @trigger_type.to_s,
      defaultWorkflow: @default_workflow.to_hash,
      enableable: @enableable,
      constraints: @constraints
    }
    hash[:recommendedFieldOptionId] = @recommended_field_option_id if @recommended_field_option_id
    hash
  end

  private

  # The recommended status option id comes from the default workflow's
  # `get_project_items` action arguments, which `MemexProjectWorkflow.default_*_workflow_attributes`
  # populates via the recommended-status helper. Extracting here keeps the FE
  # API self-documenting (`recommendedFieldOptionId`) without duplicating the
  # selection logic.
  def extract_recommended_field_option_id(default_workflow_attributes)
    return nil unless TRIGGER_TYPES_WITH_RECOMMENDED_FIELD_OPTION.include?(@trigger_type)

    actions = default_workflow_attributes[:actions_attributes] || []
    get_project_items_action = actions.find { |action| action[:action_type] == :get_project_items }
    get_project_items_action&.dig(:arguments, :fieldOptionId)
  end
end
