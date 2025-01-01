# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class ProjectNextFieldConfiguration < Platform::Unions::Base
      description "Configurations for project next fields."
      required_capabilities [:mobile_only_schema_mask]

      possible_types(
        Objects::ProjectNextField,
        Objects::ProjectNextSingleSelectField,
        Objects::ProjectNextIterationField
      )
    end
  end
end
