# typed: true
# frozen_string_literal: true

class Actions::WorkflowRunExecutionData
  attr_accessor :referenced_workflows

  def initialize(values = {})
    @referenced_workflows = values[:referenced_workflows]
  end
end
