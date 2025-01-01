# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module ProjectV2Owner
      include Platform::Interfaces::Base
      include Helpers::PrivateProfile
      include Helpers::ProjectV2Sorter

      description "Represents an owner of a project."
      global_id_field :id, description: "The Node ID of the ProjectV2Owner object"

      visibility :public, environments: [:dotcom, :enterprise]

      field :project_v2, Objects::ProjectV2,
        minimum_accepted_scopes: ["read:project"],
        description: "Find a project by number.",
        null: true,
        visibility: {
          public: { environments: [:dotcom, :enterprise] },
        } do
        argument :number, Integer, "The project number.", required: true
      end

      def project_v2(number:)
        # If this is called for an issue or PR, the search is done in the associated projects.
        if @object.is_a?(::Issue) || @object.is_a?(::PullRequest)
          return @object.async_memex_projects.then do |pp|
            Helpers::ProjectV2.async_validate_project_by_number(
              pp.detect { |p| p.number == number },
              number,
              @context[:permission]
            )
          end
        end

        Loaders::ProjectV2ByNumber.load(@object, @context[:viewer], number).then do |project|
          Helpers::ProjectV2.async_validate_project_by_number(project, number, @context[:permission])
        end
      end

      field :projects_v2_by_number, Connections.define(Objects::ProjectV2),
        minimum_accepted_scopes: ["read:project"],
        description: "Finds all valid projects by a list of their numbers belonging to the owner.",
        numeric_pagination_enabled: true,
        null: false,
        visibility: :internal do
        argument :numbers, [Integer], "A list of project numbers belonging to the owner. A max of 20 numbers can be passed.", required: true, validates: { length: { minimum: 1, maximum: 20 } }
        argument :order_by, Inputs::ProjectV2Order,
          "How to order the returned projects.", required: false, default_value: { field: "number", direction: "DESC" }
      end

      def projects_v2_by_number(**arguments)
        Loaders::ProjectV2ByNumber.load_all(@object, @context[:viewer], arguments[:numbers])
          .then { |projects| Helpers::ProjectV2.async_validate_readable_projects(projects, @context[:permission]) }
          .then { |projects| sort_projects_v2(projects, arguments[:order_by], nil, @context[:viewer]) }
      end

      field :projects_v2,
        resolver: private_profile_collection(Resolvers::ProjectsV2),
        minimum_accepted_scopes: ["read:project"],
        numeric_pagination_enabled: true,
        visibility: {
          public:  { environments: [:dotcom, :enterprise] },
        },
        description: "A list of projects under the owner.",
        connection: true
    end
  end
end
