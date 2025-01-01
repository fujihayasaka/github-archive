# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class ProjectV2FieldConfiguration < Platform::Unions::Base
      description "Configurations for project fields."

      visibility :public, environments: [:dotcom, :enterprise]

      possible_types(
        Objects::ProjectV2Field,
        Objects::ProjectV2SingleSelectField,
        Objects::ProjectV2IterationField
      )
    end
  end
end
