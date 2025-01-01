# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class Deployments < Resolvers::Base
      type Connections.define(Objects::Deployment), null: false

      argument :environments, [String], "Environments to list deployments for", required: false
      argument :order_by, Inputs::DeploymentOrder, "Ordering options for deployments returned from the connection.", required: false,
        default_value: { field: "created_at", direction: "ASC" }
      argument :filter_by, Inputs::DeploymentFilters, "Filtering options for deployments returned from the connection.", required: false, feature_flag: :deployments_ux_filtering_react, visibility: :under_development
    end
  end
end
