# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class AbuseReport < Platform::Objects::Base

      description "A submitted abuse report."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_readable_by?(permission.viewer)
      end

      visibility :internal

      minimum_accepted_scopes ["site_admin"]
      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject
      global_id_field :id, description: "The Node ID of the AbuseReport object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      created_at_field
      updated_at_field

      field :reason, Enums::AbuseReportReason, description: "The reason this content was reported.", null: false
      field :reporting_user, Objects::User, description: "The user who reported the content.", null: true, method: :async_reporting_user
      field :reported_user, Objects::User, description: "The user who created the reported content.", null: true, method: :async_reported_user
      field :repository, Objects::Repository, description: "The repository the reported content belongs to.", null: true, method: :async_repository
      field :staff_accessed_repository, Objects::StaffAccessedRepository, description: "The repository the reported content belongs to, as shown in Stafftools.", null: true, method: :async_repository
      field :reported_content, Interfaces::AbuseReportable, description: "The content that was reported.", null: true
      field :zendesk_search_url, Scalars::URI, description: "The link to Zendesk results for reports for this content.", null: true, method: :async_zendesk_url
      field :is_user_report, Boolean, description: "If this AbuseReport is a report of the user", null: false, method: :user_report?
      field :is_content_report, Boolean, description: "If this AbuseReport is a report of the user's content", null: false, method: :content_report?
      field :is_resolved, Boolean, description: "Whether this AbuseReport has been marked as resolved", null: false, method: :resolved?

      def reported_content
        @object.async_reported_content.then do |content|
          next unless content.present?

          if content.is_a?(::Gist)
            content
          else
            content.async_repository.then do |repo|
              repo.async_readable_by?(context[:viewer]).then do |is_readable|
                # if a repository is made private after abuse is reported,
                # we need to return `nil` instead of leaking private content
                # to site admins.
                next unless is_readable
                content
              end
            end
          end
        end
      end
    end
  end
end
