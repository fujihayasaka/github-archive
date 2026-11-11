# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateIssueFieldValue < Platform::Mutations::Base
      docs_category :issues
      include Helpers::IssueSuggestions

      description "Updates an existing issue field value for an issue."
      minimum_accepted_scopes ["public_repo"]

      argument :issue_id, ID, required: true, loads: Objects::Issue, description: "The ID of the issue."
      argument :issue_field, Inputs::IssueFieldCreateOrUpdateInput, required: true, description: "The field value to update. May include an optional `rationale` or be flagged with `suggest: true` to be stored as a pending suggestion instead of being applied directly."

      field :issue_field_value, Unions::IssueFieldValue, null: true, description: "The updated issue field value."
      field :issue, Objects::Issue, null: true, description: "The issue object."

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, issue:, **inputs)
        issue.async_repository.then do |repository|
          permission.async_owner_if_org(repository).then do |org|
            next false unless IssueFieldsFeature.enabled?(repository, actor: permission.viewer)

            permission.access_allowed?(
              :update_issue_field_values,
              resource: issue,
              current_org: org,
              repo: repository,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            )
          end
        end
      end

      def resolve(issue:, issue_field:)
        repository = issue.repository
        unless IssueFieldsFeature.enabled?(repository, actor: context[:viewer])
          raise Errors::Forbidden.new("Issue fields feature is not enabled for this repository")
        end

        # Block flagged accounts from creating suggestion or rationale records.
        # Mirrors the REST guard in `Api::Issues` for the suggestion path.
        if field_inputs_carry_suggest_or_rationale?(issue_field)
          ensure_actor_not_flagged_for_suggestions!(repository)
        end

        suggest = !!issue_field.suggest
        rationale = issue_field.rationale.presence
        confidence = resolve_confidence_level(issue_field.confidence)

        # The schema-level FF on `rationale`/`suggest` has already gated
        # visibility per viewer, but rollout is repo-scoped: re-check against
        # the issue's repository here. When the FF is off:
        #   - `suggest: true` on this single-op mutation has nothing to fall
        #     back to (the only requested op was a suggestion), so error.
        #   - `rationale` is silently dropped and the value is applied.
        if suggest || rationale
          unless update_issue_suggestions_enabled?(repository)
            if suggest
              raise Errors::Unprocessable.new("Issue suggestions are not available for this repository.")
            end
            rationale = nil
            confidence = nil
          end
        end

        # Confidence has its own flag, matching the REST API gate.
        unless update_issue_confidence_enabled?(repository)
          confidence = nil
        end

        if suggest
          persist_field_suggestion!(repository: repository, issue: issue, issue_field: issue_field, confidence: confidence)

          emit_analytics_event(issue: issue, repository: repository)
          return { issue_field_value: nil, issue: issue }
        end

        result = Platform::Helpers::IssueFieldValue.create_or_update_field_value(
          issue_field: issue_field,
          issue: issue,
          viewer: context[:viewer],
          action: "update"
        )

        if rationale
          field_id = Platform::Helpers::NodeIdentification.from_global_id(issue_field.field_id)[1].to_i
          store_field_rationale_annotation(
            issue: issue,
            repository: repository,
            actor: context[:viewer],
            field_id: field_id,
            rationale: rationale,
            confidence: confidence,
          )
        end

        emit_analytics_event(issue: issue, repository: repository)

        result
      end

      private

      # `extract_field_value` and `store_field_rationale_annotation` live in
      # `Platform::Helpers::IssueSuggestions`.

      def emit_analytics_event(issue:, repository:)
        org_name = repository.owner.display_login
        repo_name = repository.name
        GlobalInstrumenter.instrument("analytics.event",
          actor: context[:viewer],
          category: "issue_fields_usage",
          action: "update_field_value",
          label: "source:api,mutation:updateIssueFieldValue,org:#{org_name},repo:#{repo_name}"
        )
      end
    end
  end
end
