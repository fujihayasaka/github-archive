# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SetIssueFieldValue < Platform::Mutations::Base
      docs_category :issues
      include Helpers::IssueSuggestions

      description "Sets the value of an IssueFieldValue."
      minimum_accepted_scopes ["public_repo"]

      argument :issue_id, ID, "The ID of the Issue to set the field value on.", required: true, loads: Objects::Issue
      argument :issue_fields, [Inputs::IssueFieldCreateOrUpdateInput], "The issue fields to set on the issue.", required: true
      field :issue_field_values, [Unions::IssueFieldValue], "The issue field values that were created or updated.", null: true
      field :issue, Objects::Issue, "The issue where the field values were set.", null: true

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

      def resolve(issue:, issue_fields:)
        repository = issue.repository
        unless IssueFieldsFeature.enabled?(repository, actor: context[:viewer])
          raise Errors::Forbidden.new("Issue fields feature is not enabled for this repository")
        end

        # Block flagged accounts from creating suggestion or rationale records.
        # Mirrors the REST guard in `Api::Issues` for the suggestion path.
        if field_inputs_carry_suggest_or_rationale?(issue_fields)
          ensure_actor_not_flagged_for_suggestions!(repository)
        end

        # Partition into suggested vs applied. Inputs flagged `suggest: true`
        # are routed through the PendingFieldSuggestion path (mirrors the REST
        # PATCH `/issues/:number` behavior). The schema-level FF on the
        # `rationale`/`suggest` arguments has already gated visibility, but we
        # re-check at runtime against the issue's repository since rollout is
        # repo-scoped: if the FF is off here, silently drop suggestions and
        # rationales rather than failing the whole call. Only error if every
        # input was a suggestion (nothing left to apply).
        suggestions_enabled = update_issue_suggestions_enabled?(repository)
        suggested_inputs, applied_inputs = issue_fields.partition { |f| !!f.suggest }

        unless suggestions_enabled
          if applied_inputs.empty? && suggested_inputs.any?
            raise Errors::Unprocessable.new("Issue suggestions are not available for this repository.")
          end
          suggested_inputs = []
        end

        confidence_enabled = suggestions_enabled && update_issue_confidence_enabled?(repository)
        suggested_inputs.each do |issue_field|
          persist_field_suggestion!(
            repository: repository,
            issue: issue,
            issue_field: issue_field,
            confidence: confidence_enabled ? resolve_confidence_level(issue_field.confidence) : nil,
          )
        end

        # Maps field_id => rationale text for fields being applied directly.
        # Suggested fields carry their rationale on the PendingFieldSuggestion.
        # When the FF is off, rationale is silently ignored on applied fields.
        field_rationales = T.let({}, T::Hash[Integer, String])
        field_confidences = T.let({}, T::Hash[Integer, Issues::ConfidenceThreshold::Level])
        field_value_attributes = applied_inputs.map do |issue_field|
          field_id = global_id_to_int(issue_field.field_id)
          if suggestions_enabled && issue_field.rationale.present?
            field_rationales[field_id] = issue_field.rationale
          end
          if confidence_enabled
            cf = resolve_confidence_level(issue_field.confidence)
            field_confidences[field_id] = cf if cf
          end
          build_field_value_attributes(issue_field, field_id)
        end

        # If every input was a suggestion, there's nothing to update — just emit
        # analytics and return.
        if field_value_attributes.empty?
          emit_analytics_event(issue: issue, repository: repository)
          return { issue_field_values: [], issue: issue }
        end

        issue_attributes = Issues::UpdateIssueAttributes.new(
          issue_fields: field_value_attributes
        )
        result = Issues.domain.update(issue, issue_attributes, context[:viewer])

        case result
        when GH::Result::Ok
          field_rationales.each do |field_id, rationale_text|
            store_field_rationale_annotation(
              issue: issue,
              repository: repository,
              actor: context[:viewer],
              field_id: field_id,
              rationale: rationale_text,
              confidence: field_confidences[field_id],
            )
          end

          emit_analytics_event(issue: issue, repository: repository)

          values = field_value_attributes.map do |attr|
            Issues.domain.issue_fields.get_issue_field_value(issue.repository_id, issue.id, attr.field_id)
          end.compact
          { issue_field_values: values, issue: issue }
        when GH::Result::Error::Validation
          raise Errors::Validation.new(result.message)
        when GH::Result::Error
          raise Errors::Unprocessable.new(result.message)
        end
      end

      private

      def global_id_to_int(global_id)
        Platform::Helpers::NodeIdentification.from_global_id(global_id)[1].to_i
      end

      # Build the appropriate Issues::IssueField*ValueAttributes from an input
      # that has already been resolved to an integer field_id.
      def build_field_value_attributes(issue_field, field_id)
        if issue_field.delete
          Issues::IssueFieldDeleteAttributes.new(field_id: field_id)
        elsif issue_field.text_value
          Issues::IssueFieldTextValueAttributes.new(field_id: field_id, text_value: issue_field.text_value)
        elsif issue_field.date_value
          Issues::IssueFieldDateValueAttributes.new(field_id: field_id, date_value: issue_field.date_value)
        elsif issue_field.single_select_option_id
          option_id = global_id_to_int(issue_field.single_select_option_id)
          Issues::IssueFieldSingleSelectValueAttributes.new(field_id: field_id, option_id: option_id)
        elsif issue_field.multi_select_option_ids.present?
          option_ids = issue_field.multi_select_option_ids.map do |global_id|
            Platform::Helpers::NodeIdentification.from_global_id(global_id)[1].to_i
          end
          Issues::IssueFieldMultiSelectValueAttributes.new(field_id: field_id, option_ids: option_ids)
        elsif issue_field.number_value
          Issues::IssueFieldNumberValueAttributes.new(field_id: field_id, number_value: issue_field.number_value)
        else
          raise Errors::Validation.new("You must provide a valid value to match the selected type.")
        end
      end

      # `extract_field_value` and `store_field_rationale_annotation` live in
      # `Platform::Helpers::IssueSuggestions`.

      def emit_analytics_event(issue:, repository:)
        org_name = repository.owner.display_login
        repo_name = repository.name
        GlobalInstrumenter.instrument("analytics.event",
          actor: context[:viewer],
          category: "issue_fields_usage",
          action: "set_field_values",
          label: "source:api,mutation:setIssueFieldValue,org:#{org_name},repo:#{repo_name}"
        )
      end
    end
  end
end
