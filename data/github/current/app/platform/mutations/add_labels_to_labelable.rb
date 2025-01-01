# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddLabelsToLabelable < Platform::Mutations::Base
      description "Adds labels to a labelable object."

      minimum_accepted_scopes ["public_repo"]

      argument :labelable_id, ID, "The id of the labelable object to add labels to.", required: true, loads: Interfaces::Labelable
      argument :label_ids, [ID], "The ids of the labels to add.", required: true, loads: Objects::Label

      error_fields
      field :labelable, Interfaces::Labelable, "The item that was labeled.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, labelable:, **inputs)
        permission.async_repo_and_org_owner(labelable).then do |repo, org|
          permission.access_allowed?(:add_label, repo: repo, resource: labelable, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(labelable:, labels:, execution_errors:, **inputs)
        record = labelable
        issue = record.is_a?(PullRequest) ? record.issue : record

        unless issue.labelable_by?(actor: context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to add labels in this repository.")
        end

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

          label_in_other_repository = labels.find { |label| label.repository_id != issue.repository_id }
          if label_in_other_repository
            GitHub.dogstats.increment "graphql.mutation.add_labels_to_labelable.cross_repository"
            raise Errors::NotFound.new("The label ('#{label_in_other_repository.global_relay_id}') and issue ('#{issue.global_relay_id}') don't belong to the same repository")
          end

          begin
            issue.add_labels(labels) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
          rescue ActiveRecord::RecordInvalid => ex
            raise Errors::ArgumentLimit.new(ex)
          end


          if issue.valid?
            {
              labelable: record,
              errors: [],
            }
          else
            Platform::UserErrors.append_legacy_mutation_model_errors_to_context(issue, execution_errors)

            {
              labelable: nil,
              errors: Platform::UserErrors.mutation_errors_for_model(issue),
            }
          end
        end
      end
    end
  end
end
