# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    # Rejects one or more pending issue suggestions on a single issue atomically.
    # Any failure rolls back the entire batch so callers can either reject every
    # suggestion or none.
    class RejectPendingIssueSuggestions < Platform::Mutations::Base
      docs_category :issues
      description "Rejects a batch of pending issue suggestions on an issue atomically."
      graphql_name "RejectPendingIssueSuggestions"

      visibility :internal

      minimum_accepted_scopes ["repo"]

      error_fields

      argument :issue_id, ID, "The ID of the issue the suggestions apply to.", loads: Objects::Issue, required: true
      argument :actor_id, ID, "The ID of the actor whose suggestions to reject.", loads: Interfaces::Actor, required: true
      argument :suggestions, [Platform::Inputs::PendingIssueSuggestionRef],
        "The pending suggestions to reject. All are rejected atomically; any failure rolls back the entire batch.",
        required: true

      field :issue, Objects::Issue, "The issue the suggestions were rejected from.", null: true

      MAX_SUGGESTIONS_PER_BATCH = 50

      def self.async_api_can_modify?(permission, issue:, **inputs)
        permission.async_repo_and_org_owner(issue).then do |repo, org|
          permission.access_allowed?(
            :triage_issue,
            resource: issue,
            repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(issue:, actor:, suggestions:, **inputs)
        if suggestions.empty?
          raise Errors::Unprocessable, "At least one suggestion must be provided."
        end

        if suggestions.length > MAX_SUGGESTIONS_PER_BATCH
          raise Errors::ArgumentLimit.new("A maximum of #{MAX_SUGGESTIONS_PER_BATCH} suggestions can be rejected per request.")
        end

        issue.async_repository.then do |repository|
          unless repository.has_issues?
            raise Errors::Forbidden, "Repository has issues disabled."
          end

          context[:permission].authorize_content(:issue, :update, issue: issue, repo: repository)

          check_database_resource_update_rate_limit!(resource: issue, current_user: context[:viewer])

          Issue.transaction do # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
            suggestions.each do |suggestion_input|
              kind = suggestion_input[:kind]
              case kind
              when "TYPE"
                reject_type_suggestion(issue: issue, repository: repository, actor: actor, suggestion_input: suggestion_input)
              when "LABEL"
                reject_label_suggestion(issue: issue, repository: repository, actor: actor, suggestion_input: suggestion_input)
              when "FIELD"
                reject_field_suggestion(issue: issue, repository: repository, actor: actor, suggestion_input: suggestion_input)
              else
                raise Errors::Unprocessable, "Unknown suggestion kind: #{kind}."
              end
            end
          end

          { issue: issue, errors: [] }
        end
      end

      private

      def reject_type_suggestion(issue:, repository:, actor:, suggestion_input:)
        issue_type_id = suggestion_input[:issue_type_id]
        raise Errors::Unprocessable, "issueTypeId is required for TYPE suggestions." unless issue_type_id.present?

        issue_type = Helpers::IssueTypes.load_by_id(issue_type_id, context)
        raise Errors::Unprocessable, "Issue type is required." unless issue_type

        if intent_migration_enabled?
          intent = ::Issues::UpdateIntent.find_active(
            issue_id: issue.id,
            repository_id: repository.id,
            action: "set_type",
            actor_id: actor.id,
          )

          unless intent
            raise Errors::NotFound, "No pending type suggestion found for this issue and actor."
          end

          ::Issues::UpdateIntent.update_state(
            id: intent.id,
            issue_id: issue.id,
            repository_id: repository.id,
            new_state: ::Issues::UpdateIntent::STATE_DISMISSED,
            resolved_by: context[:viewer].id,
          )
        else
          suggestion = ::Issues::PendingTypeSuggestion.find(
            repository_id: repository.id,
            issue_id: issue.id,
            issue_type_id: T.must(issue_type.id),
            actor_id: actor.id,
          )

          unless suggestion
            raise Errors::NotFound, "No pending type suggestion found for this issue, type, and actor."
          end

          unless suggestion["state"] == ::Issues::PendingTypeSuggestion::STATE_PENDING
            raise Errors::Unprocessable, "Suggestion is not pending (state: #{suggestion["state"]})."
          end

          ::Issues::PendingTypeSuggestion.update_state(
            repository_id: repository.id,
            issue_id: issue.id,
            issue_type_id: T.must(issue_type.id),
            state: ::Issues::PendingTypeSuggestion::STATE_REJECTED,
            actor_id: actor.id,
          )
        end
      end

      def reject_label_suggestion(issue:, repository:, actor:, suggestion_input:)
        label_global_id = suggestion_input[:label_id]
        raise Errors::Unprocessable, "labelId is required for LABEL suggestions." unless label_global_id.present?

        label = load_label(label_global_id)
        raise Errors::NotFound, "Label not found." unless label

        if intent_migration_enabled?
          intent = ::Issues::UpdateIntent.find_active(
            issue_id: issue.id,
            repository_id: repository.id,
            action: "set_labels",
            actor_id: actor.id,
            target_id: T.must(label.id),
          )

          unless intent
            raise Errors::NotFound, "No pending label suggestion found for this issue, label, and actor."
          end

          ::Issues::UpdateIntent.update_state(
            id: intent.id,
            issue_id: issue.id,
            repository_id: repository.id,
            new_state: ::Issues::UpdateIntent::STATE_DISMISSED,
            resolved_by: context[:viewer].id,
          )
        else
          suggestion = ::Issues::PendingLabelSuggestion.find(
            repository_id: repository.id,
            issue_id: issue.id,
            label_id: T.must(label.id),
            actor_id: actor.id,
          )

          unless suggestion
            raise Errors::NotFound, "No pending label suggestion found for this issue, label, and actor."
          end

          unless suggestion["state"] == ::Issues::PendingLabelSuggestion::STATE_PENDING
            raise Errors::Unprocessable, "Suggestion is not pending (state: #{suggestion["state"]})."
          end

          ::Issues::PendingLabelSuggestion.update_state(
            repository_id: repository.id,
            issue_id: issue.id,
            label_id: T.must(label.id),
            state: ::Issues::PendingLabelSuggestion::STATE_REJECTED,
            actor_id: actor.id,
          )
        end
      end

      def reject_field_suggestion(issue:, repository:, actor:, suggestion_input:)
        issue_field_global_id = suggestion_input[:issue_field_id]
        raise Errors::Unprocessable, "issueFieldId is required for FIELD suggestions." unless issue_field_global_id.present?

        issue_field = load_issue_field(issue_field_global_id)
        raise Errors::NotFound, "Issue field not found." unless issue_field

        if intent_migration_enabled?
          intent = ::Issues::UpdateIntent.find_active(
            issue_id: issue.id,
            repository_id: repository.id,
            action: "set_field",
            actor_id: actor.id,
            target_id: T.must(issue_field.id),
          )

          unless intent
            raise Errors::NotFound, "No pending field suggestion found for this issue, field, and actor."
          end

          ::Issues::UpdateIntent.update_state(
            id: intent.id,
            issue_id: issue.id,
            repository_id: repository.id,
            new_state: ::Issues::UpdateIntent::STATE_DISMISSED,
            resolved_by: context[:viewer].id,
          )
        else
          suggestion = ::Issues::PendingFieldSuggestion.find(
            repository_id: repository.id,
            issue_id: issue.id,
            issue_field_id: T.must(issue_field.id),
            actor_id: actor.id,
          )

          unless suggestion
            raise Errors::NotFound, "No pending field suggestion found for this issue, field, and actor."
          end

          unless suggestion["state"] == ::Issues::PendingFieldSuggestion::STATE_PENDING
            raise Errors::Unprocessable, "Suggestion is not pending (state: #{suggestion["state"]})."
          end

          ::Issues::PendingFieldSuggestion.update_state(
            repository_id: repository.id,
            issue_id: issue.id,
            issue_field_id: T.must(issue_field.id),
            state: ::Issues::PendingFieldSuggestion::STATE_REJECTED,
            actor_id: actor.id,
          )
        end
      end

      def load_label(global_id)
        _, database_id = Platform::Helpers::NodeIdentification.from_global_id(global_id)
        ::Label.find_by(id: database_id)
      end

      def load_issue_field(global_id)
        _, database_id = Platform::Helpers::NodeIdentification.from_global_id(global_id)
        ::IssueField.find_by(id: database_id)
      end

      def intent_migration_enabled?
        FeatureFlag.vexi.enabled?(:issues_intent_model_migration, default: false)
      end
    end
  end
end
