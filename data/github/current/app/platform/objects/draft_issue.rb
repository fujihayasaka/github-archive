# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DraftIssue < Objects::Base
      COHORT = "2022-04-18"

      description "A draft issue within a project."

      visibility :public, environments: [:dotcom, :enterprise]

      implements_node templates: [
        [:odi, :org_id, :project_id, :draft_issue_id],
        [:udi, :user_id, :project_id, :draft_issue_id]
      ],
      as: "DI",
      ready_date: COHORT do |draft_issue|
        draft_issue.async_memex_project_item.then do |project_item|
          project_item.async_memex_project.then do |project|
            case project.owner_type
            when "Organization"
              {
                prefix: :odi,
                org_id: project.owner_id,
                project_id: project.id,
                draft_issue_id: draft_issue.id
              }
            when "User"
              {
                prefix: :udi,
                user_id: project.owner_id,
                project_id: project.id,
                draft_issue_id: draft_issue.id
              }
            else
              raise Platform::Errors::Internal, "Unknown owner type: #{project.owner_type.inspect}"
            end
          end
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_memex_project_item.then do |item|
          permission.typed_can_access?("ProjectV2Item", item).then do |pvt_perm|
            next pvt_perm
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_memex_project_item.then do |item|
          permission.typed_can_see?("ProjectV2Item", item).then do |pvt_perm|
            next pvt_perm
          end
        end
      end

      minimum_accepted_scopes ["read:org", "repo", "read:project"]

      created_at_field

      updated_at_field

      field :title, String, "The title of the draft issue", null: false

      field :body, String, description: "The body of the draft issue.", null: false

      def body
        @object.body || ""
      end

      field :body_text, String, description: "The body of the draft issue rendered to text.", null: false

      def body_text
        return Promise.resolve(GitHub::HTMLSafeString::EMPTY) if body.empty?

        @object.async_body_text.then do |body_text|
          body_text || GitHub::HTMLSafeString::EMPTY
        end
      end

      field :body_html, Scalars::HTML, description: "The body of the draft issue rendered to HTML.", null: false

      def body_html
        return Promise.resolve(GitHub::HTMLSafeString::EMPTY) if body.empty?

        @object.async_body_html.then do |body_html|
          body_html || GitHub::HTMLSafeString::EMPTY
        end
      end

      field :creator, resolver: Resolvers::ActorCreator, description: "The actor who created this draft issue.", null: true

      field :project_v2_items, Connections.define(Objects::ProjectV2Item), "List of items linked with the draft issue (currently draft issue can be linked to only one item).", connection: true, null: false, numeric_pagination_enabled: true
      def project_v2_items
        Loaders::ActiveRecord.load_all(::MemexProjectItem, [@object.memex_project_item_id].compact).then do |items|
          ArrayWrapper.new(items)
        end
      end

      field :projects_v2, Connections.define(Platform::Objects::ProjectV2), "Projects that link to this draft issue (currently draft issue can be linked to only one project).", connection: true, null: false
      def projects_v2
        @object.async_memex_project.then do |project|
          ArrayWrapper.new([project].compact)
        end
      end

      field :assignees, Connections::User, description: "A list of users to assigned to this draft issue.", connection: true, null: false

      def assignees
        @object.async_assignees.then do |users|
          ArrayWrapper.new(
            # login used for sorting is fine because it's not surfaced to the customer
            users.reject { |u| u.hide_from_user?(context[:viewer]) }.sort_by { |u| u.login } # rubocop:disable GitHub/DoNotAllowLogin
          )
        end
      end

      field :suggested_assignees, Connections::User, description: "A list of suggested users to assign to this draft issues", connection: true, null: false, required_capabilities: [:mobile_only_schema_mask] do
        argument :query, String, "If provided, searches users by login or profile name", required: false
      end

      def suggested_assignees(query: nil)
        @object.async_assignees.then do
          if query.present?
            ArrayWrapper.new(@object.filtered_assignees_list(context[:viewer], query))
          else
            available_assignees = @object
              .sorted_assignees_list(current_user: context[:viewer])
              .reject { |user| user.hide_from_user?(context[:viewer]) }

            ArrayWrapper.new(available_assignees)
          end
        end
      end
    end
  end
end
