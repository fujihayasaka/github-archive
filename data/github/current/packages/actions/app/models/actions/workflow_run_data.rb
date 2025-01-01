# typed: true
# frozen_string_literal: true

class Actions::WorkflowRunData
  attr_accessor :action
  attr_accessor :workflow_name_hint
  attr_accessor :workflow_execution_graph
  attr_accessor :completed_log_url
  attr_accessor :trigger
  attr_accessor :concurrency
  attr_accessor :workflow_run_execution_data

  # This field will only be populated for required workflows
  attr_accessor :workflow_file_checkout_sha
  attr_accessor :workflow_file_ref

  attr_accessor :tree_id
  attr_accessor :cloned_workflow_run_id

  def initialize(values = {})
    @action = values[:action]
    @workflow_name_hint = values[:workflow_name_hint]
    @completed_log_url = values[:completed_log_url]
    @trigger = values[:trigger]
    @workflow_execution_graph = values[:workflow_execution_graph]
    @concurrency = values[:concurrency]
    @workflow_run_execution_data = values[:workflow_run_execution_data]
    @workflow_file_checkout_sha = values[:workflow_file_checkout_sha]
    @workflow_file_ref = values[:workflow_file_ref]
    @tree_id = values[:tree_id]
    @cloned_workflow_run_id = values[:cloned_workflow_run_id]
  end
end
