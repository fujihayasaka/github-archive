# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class WorkflowRunOrderField < Enums::Base
      description "Properties by which workflow run connections can be ordered."

      value "CREATED_AT", "Order workflow runs by most recently created", value: "created_at"
    end
  end
end
