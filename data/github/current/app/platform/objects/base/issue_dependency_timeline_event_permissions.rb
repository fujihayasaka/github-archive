# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      # Shared permission methods for issue dependency timeline events.
      # These events track changes to issue dependencies (blocking/blocked relationships).
      module IssueDependencyTimelineEventPermissions
        extend ActiveSupport::Concern

        class_methods do
          # Determine whether the viewer can access this object via the API (called internally).
          # This is where Egress checks for OAuth scopes and GitHub Apps go.
          # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
          def async_api_can_access?(permission, issue_dependency_event)
            permission.belongs_to_issue_event(issue_dependency_event).then do |issue_event_accessible|
              next false unless issue_event_accessible

              issue_dependency_event.async_subject_as_issue_or_pull_request.then do |subject|
                next unless subject
                permission.async_repo_and_org_owner(subject).then do |subject_repo, subject_repo_org|
                  next unless subject_repo
                  permission.access_allowed?(:list_issue_timeline, resource: subject, repo: subject_repo, current_org: subject_repo_org, allow_integrations: true, allow_user_via_granular_actor: true)
                end
              end
            end
          end

          # Determine whether the viewer can see this object (called internally).
          # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
          def async_viewer_can_see?(permission, object)
            permission.belongs_to_issue(object).then do |visible|
              next false unless visible
              object.async_subject_as_issue_or_pull_request.then do |subject|
                next false unless subject

                cap_filter = permission.cap_filter
                if cap_filter
                  next false unless cap_filter.authorized_resources([subject]).any?
                end

                graphql_type_name = Platform::Helpers::NodeIdentification.type_name_from_object(subject)
                permission.typed_can_see?(graphql_type_name, subject)
              end
            end
          end
        end
      end
    end
  end
end
