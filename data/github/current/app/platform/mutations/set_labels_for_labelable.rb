# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SetLabelsForLabelable < Platform::Mutations::Base
      docs_category :issues
      include Platform::Helpers::IssueSuggestions

      description "Replaces all the labels for a labelable object with those in the provided list."

      required_capabilities [:mobile_only_schema_mask]
      minimum_accepted_scopes ["public_repo"]

      argument :labelable_id, ID, "The ID of the labelable object whose labels should be replaced.", required: true,
        loads: Interfaces::Labelable
      argument :label_ids, [ID], "A list of node IDs of labels to apply to the labelable object. If an empty list " \
        "is passed, all existing labels will be removed from the object. Mutually exclusive with `labels`.", required: false, loads: Objects::Label
      argument :labels, [Inputs::LabelUpdateInput], "A list of labels to apply to the labelable object, each with " \
        "optional `rationale` or a `suggest` flag that stores the addition as a pending suggestion. Suggested entries " \
        "do not influence the resulting label set. Mutually exclusive with `labelIds`.", required: false, as: :labels_input, feature_flag: :update_issue_suggestions

      error_fields
      field :labelable_record, Interfaces::Labelable, "The item that was labeled.", null: true

      def self.async_api_can_modify?(permission, labelable:, **inputs)
        permission.async_repo_and_org_owner(labelable).then do |repo, org|
          permission.access_allowed?(
            :replace_all_labels,
            resource: labelable,
            repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      def resolve(labelable:, labels: nil, labels_input: nil, **inputs)
        if labels.nil? && labels_input.nil?
          raise Errors::Validation.new("One of `labelIds` or `labels` must be provided.")
        end
        if labels && labels_input
          raise Errors::Unprocessable.new("`labels` and `labelIds` are mutually exclusive; provide only one.")
        end

        record = labelable.is_a?(PullRequest) ? labelable.issue : labelable
        unless record.labelable_by?(actor: context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to set labels in this repository.")
        end

        record.async_repository.then do |repository|
          if labelable.is_a?(Issue)
            if !repository.has_issues?
              raise Errors::Unprocessable::IssuesDisabled.new
            end
            context[:permission].authorize_content(:issue, :update, repo: repository)
          end

          # Block flagged accounts from creating suggestion or rationale records.
          # Mirrors the REST guard in `Api::Issues` for the suggestion path.
          if label_inputs_carry_suggest_or_rationale?(labels_input)
            ensure_actor_not_flagged_for_suggestions!(repository)
          end

          check_database_resource_update_rate_limit!(resource: record, current_user: context[:viewer])

          if @context[:permission].integration_user_request?
            record.modifying_integration = @context[:integration]
          end

          # Set .actor to the modifying user or Bot if the model expects it, to support attribution in Hydro messages
          # and webhooks
          if record.respond_to?(:actor=)
            record.actor = @context[:viewer]
          end

          # Resolve `labels` (the new object-shape arg) into the loaded label
          # objects, partitioning suggested entries from applied. Suggested
          # entries do not influence the resulting label set — they are stored
          # as `Issues::PendingLabelSuggestion`s instead.
          label_rationales = T.let({}, T::Hash[Integer, String])
          suggested_inputs = T.let([], T::Array[T.untyped])
          applied_labels = T.let(labels || [], T::Array[T.untyped])

          if labels_input
            applied_labels, suggested_inputs, label_rationales =
              partition_label_suggestion_inputs(repository, labels_input)
          end

          # Validate all labels (set + suggested) belong to the same repository
          # as the labelable.
          suggested_labels = suggested_inputs.map { |li| li[:label] }
          all_labels = applied_labels + suggested_labels
          label_in_other_repository = all_labels.find { |label| label.repository_id != record.repository_id }
          if label_in_other_repository
            GitHub.dogstats.increment "graphql.mutation.set_labels_for_labelable.cross_repository"
            raise Errors::NotFound.new("The label ('#{label_in_other_repository.global_relay_id}') and labelable ('#{record.global_relay_id}') don't belong to the same repository")
          end

          # Persist suggestions before replacing labels so that a partial
          # failure leaves a consistent state.
          persist_label_suggestions!(repository: repository, issue: record, suggested_inputs: suggested_inputs)

          GitHub.context.push(actor_id: @context[:viewer].id) do
            record.modifying_user = @context[:viewer] if record.respond_to?(:modifying_user=)
            record.replace_labels(applied_labels) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
          end

          if record.valid?
            store_label_rationale_annotations(
              issue: record,
              repository: repository,
              actor: context[:viewer],
              label_rationales: label_rationales,
            )

            {
              labelable_record: labelable,
              errors: [],
            }
          else
            {
              labelable_record: nil,
              errors: Platform::UserErrors.mutation_errors_for_model(record),
            }
          end
        end
      end
    end
  end
end
