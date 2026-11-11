# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectV2WorkflowsOrderField < Platform::Enums::Base
      description "Properties by which project workflows can be ordered."

      visibility :public, environments: [:dotcom, :enterprise]

      value "NAME", "The name of the workflow", value: "name"
      value "NUMBER", "The number of the workflow", value: "number"
      value "UPDATED_AT", "The date and time of the workflow update", value: "updated_at"
      value "CREATED_AT", "The date and time of the workflow creation", value: "created_at"
    end
  end
end
