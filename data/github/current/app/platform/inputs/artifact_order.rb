# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class ArtifactOrder < Platform::Inputs::Base
      description "Ways in which lists of artifacts can be ordered upon return."
      required_capabilities [:mobile_only_schema_mask]

      argument :field, Enums::ArtifactOrderField, "The field to order artifacts by.", required: true
      argument :direction, Enums::OrderDirection, "The direction to order artifacts by the specified field.", required: true
    end
  end
end
