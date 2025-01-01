# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class TeamChangeParentRequest < Platform::Objects::Base
      visibility :internal
      description "Requests to change the parent team of a team."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Promise.all([object.async_parent_team, object.async_child_team]).then do |parent, child|
          Promise.all([parent.async_adminable_by?(permission.viewer), child.async_adminable_by?(permission.viewer)]).then do |parent_adminable, child_adminable|
            parent_adminable || child_adminable
          end
        end
      end

      minimum_accepted_scopes ["read:org"]

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      global_id_field :id, description: "The Node ID of the TeamChangeParentRequest object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      field :child_team, Objects::Team, method: :async_child_team, description: "The team that will be adopted", null: false

      field :parent_team, Objects::Team, method: :async_parent_team, description: "The team that will become the parent of the child team", null: false

      field :requesting_team, Objects::Team, description: "The team that requested this parent change", null: false

      def requesting_team
        Promise.all([@object.async_child_team, @object.async_parent_team]).then do
          @object.requesting_team
        end
      end

      field :requested_team, Objects::Team, description: "The team that was requested in this parent change", null: false

      def requested_team
        Promise.all([@object.async_child_team, @object.async_parent_team]).then do
          @object.requested_team
        end
      end

      field :requester, Objects::User, method: :async_requester, description: "User requesting to change the parent team.", null: false

      field :approved, Boolean, method: :approved?, description: "Is the request approved?", null: false

      field :approved_by, Objects::User, method: :async_approved_by, description: "User that approved the request to change the parent team.", null: true

      url_fields prefix: :approve, description: "The HTTP URL for approving this team change parent request" do |request|
        request.async_requested_team.then do |team|
          team.async_organization.then do |org|
            template = Addressable::Template.new("/orgs/{org}/teams/change_parent_requests/{id}/approve")
            template.expand org: org.display_login, id: request.global_relay_id
          end
        end
      end

      url_fields prefix: :cancel, description: "The HTTP URL for cancelling this team change parent request" do |request|
        request.async_requested_team.then do |team|
          team.async_organization.then do |org|
            template = Addressable::Template.new("/orgs/{org}/teams/change_parent_requests/{id}/cancel")
            template.expand org: org.display_login, id: request.global_relay_id
          end
        end
      end
    end
  end
end
