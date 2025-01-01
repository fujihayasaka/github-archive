# typed: false
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateIntegrationCategory < Platform::Mutations::Base
      description "Updates a Integration category"

      visibility :internal

      minimum_accepted_scopes ["repo"]

      argument :slug, String, "The category name id", required: true
      argument :name, String, "The category name.", required: true
      argument :body, String, "The category description.", required: true
      argument :state, Enums::IntegrationFeatureState, "The state the category is currently in.", required: true

      field :integration_category, Objects::IntegrationFeature, "The new GitHub app.", null: true

      def resolve(**inputs)
        raise Errors::Unprocessable.new("You don't have permissions to perform that action.") if !IntegrationFeature.viewer_can_read?(@context[:viewer])
        integration_feature = IntegrationFeature.find_by(slug: inputs[:slug])

        integration_feature.name = inputs[:name]
        integration_feature.body = inputs[:body]
        integration_feature.state = inputs[:state].downcase

        if integration_feature.save
          { integration_category: integration_feature }
        else
          errors = integration_feature.errors.full_messages.join(", ")
          raise Errors::Unprocessable.new("Could not update integration category: #{errors}")
        end
      end
    end
  end
end
