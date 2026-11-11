# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddLabelsToLabelable < Platform::Mutations::Base
      docs_category :issues
      include Platform::Helpers::IssueSuggestions

      description "Adds labels to a labelable object."

      minimum_accepted_scopes ["public_repo"]

      argument :labelable_id, ID, "The id of the labelable object to add labels to.", required: true, loads: Interfaces::Labelable
      argument :label_ids, [ID], "The ids of the labels to add.", required: false, loads: Objects::Label
      argument :labels, [Inputs::LabelUpdateInput], "The labels to add, each with optional `rationale` or a `suggest` flag that stores the addition as a pending suggestion. Mutually exclusive with `labelIds`.", required: false, as: :labels_input, feature_flag: :update_issue_suggestions

      read_mutation_fields_from_replicas!(ApplicationRecord::Repositories)

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

      def resolve(labelable:, labels: nil, labels_input: nil, execution_errors:, **inputs)
        # `labels` (loaded from `:label_ids`) and `labels_input` (the object
        # form) are mutually exclusive. At least one of them must be provided.
        if labels && labels_input
          raise Errors::Unprocessable.new("`labels` and `labelIds` are mutually exclusive; provide only one.")
        end

        if labels.nil? && labels_input.nil?
          raise Errors::Unprocessable.new("One of `labelIds` or `labels` must be provided.")
        end

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

          # Block flagged accounts from creating suggestion or rationale records.
          # Mirrors the REST guard in `Api::Issues` for the suggestion path.
          if label_inputs_carry_suggest_or_rationale?(labels_input)
            ensure_actor_not_flagged_for_suggestions!(repository)
          end

          check_database_resource_update_rate_limit!(resource: issue, current_user: context[:viewer])

          if @context[:permission].integration_user_request?
            issue.modifying_integration = @context[:integration]
          end

          # Set .actor to the modifying user or Bot if the model expects it, to support attribution in Hydro messages
          # and webhooks
          if issue.respond_to?(:actor=)
            issue.actor = @context[:viewer]
          end

          # Partition the object form into applied/suggested/rationales. When
          # only the legacy `:label_ids` form was given, treat the loaded
          # labels as fully-applied with no rationale or suggestions.
          label_rationales = T.let({}, T::Hash[Integer, String])
          suggested_inputs = T.let([], T::Array[T.untyped])
          applied_labels = T.let(labels || [], T::Array[T.untyped])

          if labels_input
            applied_labels, suggested_inputs, label_rationales =
              partition_label_suggestion_inputs(repository, labels_input)
          end

          # Validate all labels (applied + suggested) belong to the same
          # repository as the issue.
          suggested_labels = suggested_inputs.map { |li| li[:label] }
          all_labels = applied_labels + suggested_labels
          label_in_other_repository = all_labels.find { |label| label.repository_id != issue.repository_id }
          if label_in_other_repository
            GitHub.dogstats.increment "graphql.mutation.add_labels_to_labelable.cross_repository"
            raise Errors::NotFound.new("The label ('#{label_in_other_repository.global_relay_id}') and issue ('#{issue.global_relay_id}') don't belong to the same repository")
          end

          # Persist suggestions before applying any direct add so that a
          # partial failure leaves a consistent state.
          persist_label_suggestions!(repository: repository, issue: issue, suggested_inputs: suggested_inputs)

          if applied_labels.any?
            begin
              GitHub.context.push(actor_id: @context[:viewer].id) do
                issue.modifying_user = @context[:viewer] if issue.respond_to?(:modifying_user=)
                issue.add_labels(applied_labels) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
              end
            rescue ActiveRecord::RecordInvalid => ex
              raise Errors::ArgumentLimit.new(ex)
            end
          end

          if issue.valid?
            store_label_rationale_annotations(
              issue: issue,
              repository: repository,
              actor: context[:viewer],
              label_rationales: label_rationales,
            )

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
