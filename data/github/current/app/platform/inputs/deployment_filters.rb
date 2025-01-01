# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class DeploymentFilters < Platform::Inputs::Base
      description "Ways in which to filter lists of deployments."

      argument :creator, String, "List deployments created by the given user. Pass in 'null' for deployments with no assigned user, and '*' for deployments for any user", required: false
      argument :created_at, Scalars::DateTime, "List deployments created on or after the given date.", required: false
      argument :updated_at, Scalars::DateTime, "List deployments updated on or after the given date.", required: false
      argument :environment, String, "List deployments for the given environment.", required: false
      argument :ref, String, "List deployments for the given ref.", required: false
      argument :state, [Enums::DeploymentState], "List deployments filtered by the list of states given.", required: false
      argument :sha, String, "List deployments for the given sha.", required: false

      # Preferred fields
      argument :environments, [String], "List deployments to any of the given environments", required: false
      argument :states, [Enums::DeploymentState], "List deployments with a current state matching any of the states given.", required: false
      argument :refs, [String], "List deployments from any of the given branches, tags, or commit SHAs", required: false
      argument :creators, [String], "List deployments created by any of the given users", required: false
    end
  end
end
