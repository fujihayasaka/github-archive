# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    class IssueForm < Platform::Objects::Base
      include GitHub::UTF8
      visibility :under_development

      description "A repository issue form."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig { params(permission: T.untyped, form: T.untyped).returns(Promise[T::Boolean]) }
      def self.async_api_can_access?(permission, form)
        permission.async_repo_and_org_owner(form).then do |repo, org|
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
      sig { params(permission: T.untyped, object: T.untyped).returns(Promise[T::Boolean]) }
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object)
      end

      minimum_accepted_scopes ["repo"]

      field :name, String, "The form name.", null: false
      field :description, String, "The form's purpose.", null: true, method: :about

      field :filename, String, "The template filename.", null: false, method: :filename_for_display

      field :title, String, "The suggested issue title.", null: true

      field :type, resolver: Resolvers::IssueType, description: "The suggested issue type" do
        visibility :under_development
      end
      field :labels, resolver: Resolvers::Labels, description: "The suggested issue labels", connection: true, scope: true
      field :assignees, Connections::User, resolver: Resolvers::Assignees, description: "The suggested assignees.", connection: true
      field :projects, resolver: Resolvers::ProjectsV2, description: "The suggested projects", connection: true
      field :elements, [Platform::Unions::IssueFormElements], description: "The form elements.", null: false, method: :inputs
    end
  end
end
