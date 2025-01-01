# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class WorkflowOrderField < Platform::Enums::Base
      description "Properties by which workflow connections can be ordered."

      value "NAME", "Order workflows by name.", value: "name"
      value "CREATED_AT", "Order workflows by creation time.", value: "created_at"
      value "UPDATED_AT", "Order workflows by most recent modification time.", value: "updated_at"
    end
  end
end
