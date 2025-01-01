# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2StatusUpdate < Objects::Base

      model_name "MemexProjectStatus"

      description "A status update within a project."

      class << self
        # Delegate static methods to the ProjectV2 helper.
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2
      end

      def self.async_viewer_can_see?(permission, object)
        object.async_memex_project.then do |project|
          permission.typed_can_see?("ProjectV2", project).then do |can_see_project|
            next false unless can_see_project
            # Do not return status updates from spammy users
            object.async_hide_from_user?(permission.viewer).then do |hide_from_user|
              next false if hide_from_user
              true
            end
          end
        end
      end

      minimum_accepted_scopes ["read:project"]

      PREFIX = Helpers::ProjectV2::Prefix.new("PVTSU", :opvtsu, :upvtsu)
      implements_node templates: [
        [PREFIX.org, :owner_id, :project_id, :id],
        [PREFIX.user, :owner_id, :project_id, :id],
        ],
        as: PREFIX.to_s,
        ready_date: "1970-01-01" do |status_update|
          status_update.async_memex_project.then do |project|
            project.async_owner.then do |owner|
              {
                prefix: owner.organization? ? PREFIX.org : PREFIX.user,
                owner_id: owner.id,
                project_id: project.id,
                id: status_update.id
              }
            end
          end
        end

      DeprecationNotice = {
        start_date: Date.new(2024, 10, 1),
        reason: "`databaseId` will be removed because it does not support 64-bit signed integer identifiers.",
        superseded_by: "Use `fullDatabaseId` instead.",
        owner: "dewski",
      }

      database_id_field(deprecated: DeprecationNotice)

      full_database_id_field

      created_at_field

      updated_at_field

      field :start_date, Platform::Scalars::Date, null: true, description: "The start date of the status update."
      field :target_date, Platform::Scalars::Date, null: true, description: "The target date of the status update."
      field :status, Platform::Enums::ProjectV2StatusUpdateStatus, null: true, description: "The status of the status update."
      def status
        return nil unless @object.status_id

        name = MemexProjectStatus.status_id_to_enum_string(@object.status_id)

        raise Platform::Errors::Internal, "Unexpected status update status: #{@object.status_id}" unless name

        enum = Platform::Enums::ProjectV2StatusUpdateStatus.values[name]

        raise Platform::Errors::Internal, "Unexpected status update status: #{@object.status_id}" unless enum

        T.must(enum).value
      end

      field :body, String, null: true, description: "The body of the status update."
      field :body_html, Scalars::HTML, description: "The body of the status update rendered to HTML.", null: true
      def body_html
        return nil if @object.body.nil?

        context = {
          viewer: @context[:viewer],
          cap_filter: @context[:cap_filter],
        }

        @object.async_body_html(context: context).then do |body_html|
          body_html || GitHub::HTMLSafeString::EMPTY
        end
      end

      field :creator, Interfaces::Actor, description: "The actor who created the status update.", resolver: Resolvers::ActorCreator
      field :project, Platform::Objects::ProjectV2, description: "The project that contains this status update.", null: false, method: :async_memex_project
    end
  end
end
