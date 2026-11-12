# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateLabelsForLabelable < Platform::Mutations::Base
      include Platform::Helpers::ReadFromSelectedReplicas

      description "Updates labels on a labelable object by adding and/or removing specified labels."

      visibility :internal
      minimum_accepted_scopes ["public_repo"]

      argument :labelable_id, ID, "The id of the labelable object to update labels on.", required: true, loads: Interfaces::Labelable
      argument :add_label_ids, [ID], "The ids of labels to add.", required: false, loads: Objects::Label, as: :labels_to_add
      argument :remove_label_ids, [ID], "The ids of labels to remove.", required: false, loads: Objects::Label, as: :labels_to_remove

      read_arguments_from_replicas!

      read_mutation_fields_from_replicas!(ApplicationRecord::Repositories)

      error_fields
      field :labelable, Interfaces::Labelable, "The item that was updated.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, labelable:, labels_to_add: [], labels_to_remove: [], **inputs)
        permission.async_repo_and_org_owner(labelable).then do |repo, org|
          can_add = labels_to_add.blank? || permission.access_allowed?(:add_label, repo: repo, resource: labelable, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          can_remove = labels_to_remove.blank? || permission.access_allowed?(:remove_label, repo: repo, resource: labelable, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          can_add && can_remove
        end
      end

      def resolve(labelable:, labels_to_add: [], labels_to_remove: [], execution_errors:, **inputs)
        labels_to_add ||= []
        labels_to_remove ||= []

        if labels_to_add.empty? && labels_to_remove.empty?
          raise Errors::Unprocessable.new("At least one of `addLabelIds` or `removeLabelIds` must be provided.")
        end

        record = labelable
        issue = record.is_a?(PullRequest) ? record.issue : record

        # Discussion implements the Labelable interface, but this mutation is currently
        # only used for Issues on the client (see github/github-ui#13236). We reject
        # Discussion at runtime rather than restricting at the schema level (e.g., via a
        # Union type) to keep the argument contract aligned with the existing Labelable
        # interface used by other label mutations.
        if record.is_a?(Discussion)
          raise Errors::Unprocessable.new("Diff-based label updates are not yet supported for discussions.")
        end

        unless issue.labelable_by?(actor: context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to modify labels in this repository.")
        end

        read_from_selected_replicas([ApplicationRecord::Repositories]) do
          issue.async_repository.then do |repository|
            if record.is_a?(Issue) && !repository.has_issues?
              raise Errors::Unprocessable::IssuesDisabled.new
            end

            context[:permission].authorize_content(:issue, :update, repo: repository)

            check_database_resource_update_rate_limit!(resource: issue, current_user: context[:viewer])

            if @context[:permission].integration_user_request?
              issue.modifying_integration = @context[:integration]
            end

            # Set .actor to the modifying user or Bot if the model expects it, to support attribution in Hydro messages
            # and webhooks
            if issue.respond_to?(:actor=)
              issue.actor = @context[:viewer]
            end

            # Validate all labels belong to the same repository as the issue
            all_labels = labels_to_add + labels_to_remove
            label_in_other_repository = all_labels.find { |label| label.repository_id != issue.repository_id }
            if label_in_other_repository
              GitHub.dogstats.increment "graphql.mutation.update_labels_for_labelable.cross_repository"
              raise Errors::NotFound.new("The label ('#{label_in_other_repository.global_relay_id}') and issue ('#{issue.global_relay_id}') don't belong to the same repository")
            end

            result = issue.update_labels(labels_to_add: labels_to_add, labels_to_remove: labels_to_remove) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)

            unless result
              raise Errors::ArgumentLimit.new(ActiveRecord::RecordInvalid.new(issue))
            end

            {
              labelable: record,
              errors: [],
            }
          end
        end
      end
    end
  end
end
