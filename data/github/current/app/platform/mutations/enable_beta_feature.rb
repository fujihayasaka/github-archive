# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class EnableBetaFeature < Platform::Mutations::Base
      description "Enables a beta feature that the user has not enrolled in"
      visibility :internal, environments: [:dotcom]
      minimum_accepted_scopes ["user"]

      argument :name, String, "The name of the feature to be enabled.", required: true

      def resolve(**inputs)
        context[:viewer].enable_feature_preview(inputs[:name])
      end
    end
  end
end
