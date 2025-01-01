# typed: false
# frozen_string_literal: true

module Platform
  module Interfaces
    module ProjectOwner
      include Platform::Interfaces::Base
      include Helpers::PrivateProfile

      description "Represents an owner of a Project."

      global_id_field :id, description: "The Node ID of the ProjectOwner object"

      field :project, Objects::Project, minimum_accepted_scopes: ["public_repo"], description: "Find project by number.", null: true, visibility: :public do
        argument :number, Integer, "The project number to find.", required: true
      end

      def project(**arguments)
        Loaders::ProjectByNumber.load(@object, arguments[:number])
      end

      field :viewer_can_create_projects, Boolean, description: "Can the current viewer create new projects on this owner.", null: false, visibility: :public

      def viewer_can_create_projects
        # TODO: Use batch ability loader to check permissions
        result = @context[:viewer] && Project.viewer_can_create_projects?(project_owner: @object, viewer: @context[:viewer])
        result ? true : false
      end

      field :is_enterprise_managed, Boolean, visibility: :internal, description: "Is the project owner (organization, user, or a repo) managed by an Identity Provider", null: false
      def is_enterprise_managed
        case @object
        when Repository, Organization
          object.async_business.then do |business|
            next false if business.nil?

            business.enterprise_managed_user_enabled?
          end
        when User
          object.async_enterprise_managed_business.then do |business|
            next false if business.nil?

            business.enterprise_managed_user_enabled?
          end
        end
      end

      field :projects, resolver: private_profile_collection(Resolvers::Projects), minimum_accepted_scopes: ["public_repo"], numeric_pagination_enabled: true, visibility: :public, description: "A list of projects under the owner.", connection: true

      url_fields prefix: :projects, visibility: :public, description: "The HTTP URL listing owners projects"
    end
  end
end
