# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module ProjectNextOwner
      include Platform::Interfaces::Base
      include Helpers::PrivateProfile

      mobile_only true
      description "Represents an owner of a project."
      global_id_field :id,  description: "The Node ID of the ProjectNextOwner object"

      field :project_next, Objects::ProjectNext,
        minimum_accepted_scopes: ["read:org", "repo"],
        description: "Find a project by project number.",
        null: true do
        argument :number, Integer, "The project number.", required: true
      end

      def project_next(**arguments)
        Platform::Helpers::ProjectNext.ensure_project_next_api_availability(@context[:viewer], @context[:oauth_app])

        # If this is called for an issue or PR, the search is done in the associated projects.
        if @object.is_a?(::Issue) || @object.is_a?(::PullRequest)
          return @object.async_memex_projects.then { |pp| pp&.detect { |p| p.number == arguments[:number] } }
        end

        Loaders::ProjectNextByNumber.load(@object, @context[:viewer], arguments[:number])
      end

      field :projects_next,
        resolver: private_profile_collection(Resolvers::ProjectsNext),
        minimum_accepted_scopes: ["read:org", "repo"],
        numeric_pagination_enabled: true,
        description: "A list of projects under the owner.",
        connection: true
    end
  end
end
