# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class WorkflowDispatchInput < Platform::Inputs::Base
      docs_category :actions
      description "Inputs for dispatching a workflow. Not all workflow dispatches require inputs."

      argument :title_id, String, "The title of the dispatch input", required: true
      argument :value, String, "The value of dispatch input", required: true
    end
  end
end
