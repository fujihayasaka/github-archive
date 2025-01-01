# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2ItemFieldPullRequestValue < Platform::Objects::Base
      description "The value of a pull request field in a Project item."

      class << self
        # Delegate static methods to the ProjectV2 helper.
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2ItemFieldValue
        delegate :async_viewer_can_see?, to: Platform::Helpers::ProjectV2ItemFieldValue
      end

      visibility :public, environments: [:dotcom, :enterprise]

      minimum_accepted_scopes ["read:project"]

      field :pull_requests, Connections.define(Objects::PullRequest), description: "The pull requests for this field", null: true do
        argument :order_by, Inputs::PullRequestOrder, "Ordering options for pull requests.", required: false, default_value: { field: "created_at", direction: "ASC" }
      end
      def pull_requests(**args)
        Helpers::ProjectV2.order_objects(@object.pull_requests, args[:order_by])
      end

      field :field, Platform::Unions::ProjectV2FieldConfiguration,  description: "The field that contains this value.", null: false
    end
  end
end
