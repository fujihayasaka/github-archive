# typed: true
# frozen_string_literal: true

module Platform::Objects::Query::Features
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  included do
    T.bind(self, T.class_of(Platform::Objects::Base))
    field :toggleable_feature, Objects::ToggleableFeature, description: "Find toggleable feature by slug.", null: true, minimum_accepted_scopes: ["devtools"], visibility: :internal, map_to_service: :features do
      argument :slug, String, "The toggleable feature slug.", required: true
    end

    def toggleable_feature(**arguments)
      ::Feature.find_by(slug: arguments[:slug])
    end

    field :toggleable_features, Connections.define(Objects::ToggleableFeature), description: "Returns a list of toggleable features.", null: true, minimum_accepted_scopes: ["devtools"], visibility: :internal, map_to_service: :features

    def toggleable_features
      ::Feature.all
    end
  end
end
