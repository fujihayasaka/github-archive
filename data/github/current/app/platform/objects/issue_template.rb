# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssueTemplate < Platform::Objects::Base
      include GitHub::UTF8

      description "A repository issue template."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, template)
        permission.async_repo_and_org_owner(template).then do |repo, org|
          permission.access_allowed?(
            :list_issue_templates,
            resource: repo,
            current_repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object)
      end


      minimum_accepted_scopes ["repo"]

      field :name, String, "The template name.", null: false
      field :about, String, "The template purpose.", null: true
      field :filename, String, "The template filename.", null: false

      def filename
        utf8(@object.filename&.dup)
      end

      field :title, String, "The suggested issue title.", null: true
      field :body, String, "The suggested issue body.", null: true

      field :labels, resolver: Resolvers::Labels, description: "The suggested issue labels", connection: true, scope: true
      field :assignees, Connections::User, resolver: Resolvers::Assignees, description: "The suggested assignees.", connection: true
      field :type, resolver: Resolvers::IssueType, description: "The suggested issue type", feature_flag: :issue_types
    end
  end
end
