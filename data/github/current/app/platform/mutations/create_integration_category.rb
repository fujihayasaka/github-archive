# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateIntegrationCategory < Platform::Mutations::Base
      description "Creates a new Integration category"

      visibility :internal

      minimum_accepted_scopes ["repo"]

      argument :name, String, "The category name.", required: true
      argument :body, String, "The category description.", required: true
      argument :state, Enums::IntegrationFeatureState, "The state the category is currently in.", required: true

      field :integration_category, Objects::IntegrationFeature, "The new GitHub app.", null: true

      def resolve(**inputs)
        raise Errors::Unprocessable.new("You don't have permissions to perform that action.") if !IntegrationFeature.viewer_can_read?(@context[:viewer])
        integration_feature = IntegrationFeature.new(
          name:  inputs[:name],
          body: inputs[:body],
          state: inputs[:state].downcase,
        )

        if integration_feature.save
          { integration_category: integration_feature }
        else
          errors = integration_feature.errors.full_messages.join(", ")
          raise Errors::Unprocessable.new("Could not create integration category: #{errors}")
        end
      end
    end
  end
end
