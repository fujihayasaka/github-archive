# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    class IssueType < Platform::Objects::Base
      extend T::Sig

      graphql_name "IssueType"
      scopeless_tokens_as_minimum
      feature_flag :issue_types

      description "Represents the type of Issue."

      implements_node templates: [[:it, :owner_id, :id]], as: "IT", ready_date: "1970-01-01" do |issue_type|
        {
          prefix: :it,
          owner_id: issue_type.owner_id,
          id: issue_type.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig { params(permission: T.untyped, issue_type: ::IssueType).returns(T.any(T::Boolean, Promise[T::Boolean])) }
      def self.async_api_can_access?(permission, issue_type)
        issue_type.async_owner.then do |owner|
          permission.access_allowed?(
            :read_org_issue_types,
            resource: owner,
            issue_type: issue_type,
            current_org: owner,
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig { params(permission: T.untyped, issue_type: ::IssueType).returns(T.any(T::Boolean, Promise[T::Boolean])) }
      def self.async_viewer_can_see?(permission, issue_type)
        issue_type.async_owner.then do |owner|
          permission.viewer.present? && owner.issue_types_enabled? || false
        end
      end

      field :is_enabled, Boolean, "The issue type's enabled state.", null: false, method: :enabled
      field :name, String, "The issue type's name.", null: false
      field :description, String, "The issue type's description.", null: true
      field :color, Enums::IssueTypeColor, description: "The issue type's color.", null: false
      field :is_private, Boolean, "Whether the issue type is publicly visible.", null: false, method: :private

      field :issues, resolver: Resolvers::Issues, description: "The issues with this issue type in the given repository.", connection: true do
        argument :repository_id, ID, "Target repository to load the issues from.", required: true
      end
    end
  end
end
