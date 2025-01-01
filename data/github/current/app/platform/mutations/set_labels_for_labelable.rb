# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SetLabelsForLabelable < Platform::Mutations::Base
      description "Replaces all the labels for a labelable object with those in the provided list."

      required_capabilities [:mobile_only_schema_mask]
      minimum_accepted_scopes ["public_repo"]

      argument :labelable_id, ID, "The ID of the labelable object whose labels should be replaced.", required: true,
        loads: Interfaces::Labelable
      argument :label_ids, [ID], "A list of node IDs of labels to apply to the labelable object. If an empty list " \
        "is passed, all existing labels will be removed from the object.", required: true, loads: Objects::Label

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

      def resolve(labelable:, labels:, **inputs)
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

          if @context[:permission].integration_user_request?
            record.modifying_integration = @context[:integration]
          end

          # Set .actor to the modifying user or Bot if the model expects it, to support attribution in Hydro messages
          # and webhooks
          if record.respond_to?(:actor=)
            record.actor = @context[:viewer]
          end

          label_in_other_repository = labels.find { |label| label.repository_id != record.repository_id }
          if label_in_other_repository
            GitHub.dogstats.increment "graphql.mutation.set_labels_for_labelable.cross_repository"
            raise Errors::NotFound.new("The label ('#{label_in_other_repository.global_relay_id}') and labelable ('#{record.global_relay_id}') don't belong to the same repository")
          end

          record.replace_labels(labels)
          if record.valid?
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
