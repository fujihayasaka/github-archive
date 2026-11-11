# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DisableBetaFeature < Platform::Mutations::Base
      description "Disables a beta feature that the user has been enabled"
      visibility :internal, environments: [:dotcom]
      minimum_accepted_scopes ["user"]

      argument :name, String, "The name of the feature to be disabled.", required: true

      def resolve(**inputs)
        context[:viewer].disable_feature_preview(inputs[:name])
      end
    end
  end
end
