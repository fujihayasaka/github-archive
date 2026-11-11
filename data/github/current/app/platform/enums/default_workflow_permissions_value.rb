# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DefaultWorkflowPermissionsValue < Platform::Enums::Base
      docs_category :actions
      description "The possible default workflow permissions levels."
      visibility :internal

      value "READ", "Read-only access.", value: "read"
    end
  end
end
