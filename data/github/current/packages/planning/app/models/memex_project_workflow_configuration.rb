# typed: true
# frozen_string_literal: true

class MemexProjectWorkflowConfiguration
  attr_reader :default_workflow, :enableable, :constraints, :trigger_type

  def initialize(default_workflow_attributes:, actor:)
    @default_workflow = MemexProjectWorkflow.new(default_workflow_attributes)
    @trigger_type = default_workflow_attributes[:trigger_type]
    @enableable = MemexProjectWorkflow.trigger_type_is_enableable(@trigger_type, actor)
    @constraints = {
      "contentTypes": MemexProjectWorkflow.get_valid_content_types_for_trigger_type(@trigger_type)
    }
  end

  def to_hash
    {
      triggerType: @trigger_type.to_s,
      defaultWorkflow: @default_workflow.to_hash,
      enableable: @enableable,
      constraints: @constraints
    }
  end
end
