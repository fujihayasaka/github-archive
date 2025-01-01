# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemoveLabelsFromLabelable < Platform::Mutations::Base
      include Platform::Helpers::ReadFromSelectedReplicas

      description "Removes labels from a Labelable object."

      minimum_accepted_scopes ["public_repo"]

      argument :labelable_id, ID, "The id of the Labelable to remove labels from.", required: true, loads: Interfaces::Labelable
      argument :label_ids, [ID], "The ids of labels to remove.", required: true, loads: Objects::Label

      read_arguments_from_replicas!

      error_fields
      field :labelable, Interfaces::Labelable, "The Labelable the labels were removed from.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, labelable:, **inputs)
        permission.async_repo_and_org_owner(labelable).then do |repo, org|
          permission.access_allowed?(:remove_label, repo: repo, resource: labelable, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(labelable:, labels:, execution_errors:, **inputs)
        record = labelable
        issue = record.is_a?(PullRequest) ? record.issue : record

        read_from_selected_replicas([ApplicationRecord::Repositories]) do
          issue.async_repository.then do |repository|
            if record.is_a?(Issue) && !repository.has_issues?
              raise Errors::Unprocessable::IssuesDisabled.new
            end

            context[:permission].authorize_content(:issue, :update, repo: repository)

            # Set .actor to the modifying user or Bot if the model expects it, to support attribution in Hydro messages
            # and webhooks
            if issue.respond_to?(:actor=)
              issue.actor = @context[:viewer]
            end

            if issue.delete_labels(labels)
              {
                labelable: record,
                errors: [],
              }
            else
              Platform::UserErrors.append_legacy_mutation_model_errors_to_context(issue, execution_errors)

              {
                labelable_record: nil,
                errors: Platform::UserErrors.mutation_errors_for_models(labels, path_prefix: %w[input labels]),
              }
            end
          end
        end
      end
    end
  end
end
