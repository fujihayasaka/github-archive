# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    # Applies one or more pending issue suggestions to a single issue.
    # Each suggestion is applied via its own write path; FIELD suggestions go
    # through `Issues.domain.update` which cannot run inside a wrapping transaction,
    # so suggestions are applied sequentially rather than in one DB transaction.
    class ApplyPendingIssueSuggestions < Platform::Mutations::Base
      docs_category :issues
      description "Applies a batch of pending issue suggestions to an issue."
      graphql_name "ApplyPendingIssueSuggestions"

      visibility :internal

      minimum_accepted_scopes ["repo"]

      error_fields

      extras [:execution_errors]

      argument :issue_id, ID, "The ID of the issue the suggestions apply to.", loads: Objects::Issue, required: true
      argument :actor_id, ID, "The ID of the actor whose suggestions to apply.", loads: Interfaces::Actor, required: true
      argument :suggestions, [Platform::Inputs::PendingIssueSuggestionRef],
        "The pending suggestions to apply.",
        required: true

      field :issue, Objects::Issue, "The updated issue.", null: true

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

      def resolve(issue:, actor:, suggestions:, execution_errors:, **inputs)
        if suggestions.empty?
          raise Errors::Unprocessable, "At least one suggestion must be provided."
        end

        if suggestions.length > MAX_SUGGESTIONS_PER_BATCH
          raise Errors::ArgumentLimit.new("A maximum of #{MAX_SUGGESTIONS_PER_BATCH} suggestions can be applied per request.")
        end

        issue.async_repository.then do |repository|
          unless repository.has_issues?
            raise Errors::Forbidden, "Repository has issues disabled."
          end

          context[:permission].authorize_content(:issue, :update, issue: issue, repo: repository)

          check_database_resource_update_rate_limit!(resource: issue, current_user: context[:viewer])

          org = repository.organization

          if context[:permission].integration_user_request?
            issue.modifying_integration = context[:integration]
            issue.performed_via_integration = context[:integration]
          end

          if issue.respond_to?(:actor=)
            issue.actor = context[:viewer]
          end

          # NOTE: We intentionally do not wrap this loop in a single transaction.
          # FIELD suggestions go through `Issues.domain.update`, which refuses to run
          # inside an open transaction (raises `Issues::Domain::CalledInsideTransaction`).
          # Each individual suggestion still applies atomically via its own write path.
          suggestions.each do |suggestion_input|
            kind = suggestion_input[:kind]
            case kind
            when "TYPE"
              apply_type_suggestion(issue: issue, repository: repository, org: org,
                actor: actor, suggestion_input: suggestion_input, execution_errors: execution_errors)
            when "LABEL"
              apply_label_suggestion(issue: issue, repository: repository, org: org,
                actor: actor, suggestion_input: suggestion_input, execution_errors: execution_errors)
            when "FIELD"
              apply_field_suggestion(issue: issue, repository: repository, org: org,
                actor: actor, suggestion_input: suggestion_input)
            else
              raise Errors::Unprocessable, "Unknown suggestion kind: #{kind}."
            end
          end

          { issue: issue, errors: [] }
        end
      end

      private

      def apply_type_suggestion(issue:, repository:, org:, actor:, suggestion_input:, execution_errors:)
        unless context[:permission].access_allowed?(:set_issue_type,
          resource: issue, repo: repository, current_org: org,
          allow_integrations: true, allow_user_via_granular_actor: true)
          raise Errors::Forbidden, "#{context[:viewer].display_login} does not have permission to set the issue type."
        end

        issue_type_id = suggestion_input[:issue_type_id]
        raise Errors::Unprocessable, "issueTypeId is required for TYPE suggestions." unless issue_type_id.present?

        issue_type = Helpers::IssueTypes.load_by_id(issue_type_id, context)
        raise Errors::Unprocessable, "Issue type is required." unless issue_type
        raise Errors::Unprocessable, "Issue type is not enabled." unless issue_type.enabled?

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

          if intent.target_value != issue_type.name
            raise Errors::Unprocessable, "Pending type suggestion does not match the issue type provided."
          end

          store_intent_type_pending_rationale(
            issue: issue,
            repository: repository,
            issue_type: issue_type,
            intent: intent,
            actor: actor,
          )

          issue.issue_type = issue_type

          unless issue.save # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
            Platform::UserErrors.append_legacy_mutation_model_errors_to_context(issue, execution_errors)
            raise Errors::Unprocessable, "Failed to apply type suggestion."
          end

          ::Issues::UpdateIntent.update_state(
            id: intent.id,
            issue_id: issue.id,
            repository_id: repository.id,
            new_state: ::Issues::UpdateIntent::STATE_APPROVED,
            resolved_by: context[:viewer].id,
          )

          ::Issues::UpdateIntent.dismiss_others_on_approve(
            approved_id: intent.id,
            issue_id: issue.id,
            repository_id: repository.id,
            action: "set_type",
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

          store_type_pending_rationale(
            issue: issue,
            repository: repository,
            issue_type: issue_type,
            suggestion: suggestion,
            actor: actor,
          )

          issue.issue_type = issue_type

          unless issue.save # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
            Platform::UserErrors.append_legacy_mutation_model_errors_to_context(issue, execution_errors)
            raise Errors::Unprocessable, "Failed to apply type suggestion."
          end

          ::Issues::PendingTypeSuggestion.update_state(
            repository_id: repository.id,
            issue_id: issue.id,
            issue_type_id: T.must(issue_type.id),
            state: ::Issues::PendingTypeSuggestion::STATE_APPLIED,
            actor_id: actor.id,
          )
        end
      end

      def apply_label_suggestion(issue:, repository:, org:, actor:, suggestion_input:, execution_errors:)
        unless context[:permission].access_allowed?(:add_label,
          resource: issue, repo: repository, current_org: org,
          allow_integrations: true, allow_user_via_granular_actor: true)
          raise Errors::Forbidden, "#{context[:viewer].display_login} does not have permission to add labels in this repository."
        end

        label_global_id = suggestion_input[:label_id]
        raise Errors::Unprocessable, "labelId is required for LABEL suggestions." unless label_global_id.present?

        label = load_label(label_global_id)
        raise Errors::NotFound, "Label not found." unless label

        unless issue.labelable_by?(actor: context[:viewer])
          raise Errors::Forbidden, "#{context[:viewer].display_login} does not have permission to add labels in this repository."
        end

        if label.repository_id != issue.repository_id
          raise Errors::NotFound, "The label and issue don't belong to the same repository."
        end

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

          begin
            issue.add_labels([label]) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
          rescue ActiveRecord::RecordInvalid => ex
            raise Errors::ArgumentLimit.new(ex)
          end

          unless issue.valid?
            Platform::UserErrors.append_legacy_mutation_model_errors_to_context(issue, execution_errors)
            raise Errors::Unprocessable, "Failed to apply label suggestion."
          end

          # Look up the labeled event we just created so we can link it via
          # issue_event_id on the intent.
          label_event = issue.events
            .joins(:issue_event_detail)
            .where(event: "labeled", actor_id: context[:viewer].id, issue_event_details: { label_id: label.id })
            .order(id: :desc).first

          store_intent_label_rationale(
            issue: issue,
            repository: repository,
            label_event: label_event,
            intent: intent,
            actor: actor,
          )

          ::Issues::UpdateIntent.update_state(
            id: intent.id,
            issue_id: issue.id,
            repository_id: repository.id,
            new_state: ::Issues::UpdateIntent::STATE_APPROVED,
            resolved_by: context[:viewer].id,
            issue_event_id: label_event&.id,
          )

          ::Issues::UpdateIntent.dismiss_others_on_approve(
            approved_id: intent.id,
            issue_id: issue.id,
            repository_id: repository.id,
            action: "set_labels",
            target_id: T.must(label.id),
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

          begin
            issue.add_labels([label]) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
          rescue ActiveRecord::RecordInvalid => ex
            raise Errors::ArgumentLimit.new(ex)
          end

          unless issue.valid?
            Platform::UserErrors.append_legacy_mutation_model_errors_to_context(issue, execution_errors)
            raise Errors::Unprocessable, "Failed to apply label suggestion."
          end

          store_label_rationale(
            issue: issue,
            repository: repository,
            label: label,
            suggestion: suggestion,
            actor: actor,
          )

          ::Issues::PendingLabelSuggestion.update_state(
            repository_id: repository.id,
            issue_id: issue.id,
            label_id: T.must(label.id),
            state: ::Issues::PendingLabelSuggestion::STATE_APPLIED,
            actor_id: actor.id,
          )
        end
      end

      def apply_field_suggestion(issue:, repository:, org:, actor:, suggestion_input:)
        unless context[:permission].access_allowed?(:triage_issue,
          resource: issue, repo: repository, current_org: org,
          allow_integrations: true, allow_user_via_granular_actor: true)
          raise Errors::Forbidden, "#{context[:viewer].display_login} does not have permission to triage issues in this repository."
        end

        unless IssueFieldsFeature.enabled?(repository.owner, actor: context[:viewer])
          raise Errors::Forbidden, "Issue fields are not enabled for this organization."
        end

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

          store_intent_field_pending_rationale(
            issue: issue,
            repository: repository,
            issue_field: issue_field,
            intent: intent,
            actor: actor,
          )

          attribute = build_field_attribute(issue_field, intent.decoded_target_value)
          issue_attributes = ::Issues::UpdateIssueAttributes.new(issue_fields: [attribute])
          result = ::Issues.domain.update(issue, issue_attributes, context[:viewer])

          if result.is_a?(GH::Result::Error)
            raise Errors::Unprocessable, "Failed to apply field suggestion: #{result.message}"
          end

          # NOTE: issue_event_id is left nil here — the IssueEvent for a field
          # change is created asynchronously by HydroIssueFieldTimelineEventsJob,
          # which will link the intent to the event when it fires.
          ::Issues::UpdateIntent.update_state(
            id: intent.id,
            issue_id: issue.id,
            repository_id: repository.id,
            new_state: ::Issues::UpdateIntent::STATE_APPROVED,
            resolved_by: context[:viewer].id,
          )

          ::Issues::UpdateIntent.dismiss_others_on_approve(
            approved_id: intent.id,
            issue_id: issue.id,
            repository_id: repository.id,
            action: "set_field",
            target_id: T.must(issue_field.id),
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

          # Store the suggester's rationale as a pending annotation BEFORE the update,
          # so the async Hydro job (HydroIssueFieldTimelineEventsJob) can consume it
          # and attach it to the IssueEvent it creates.
          store_field_pending_rationale(
            issue: issue,
            repository: repository,
            issue_field: issue_field,
            suggestion: suggestion,
            actor: actor,
          )

          attribute = build_field_attribute(issue_field, suggestion["value"])
          issue_attributes = ::Issues::UpdateIssueAttributes.new(issue_fields: [attribute])
          result = ::Issues.domain.update(issue, issue_attributes, context[:viewer])

          if result.is_a?(GH::Result::Error)
            raise Errors::Unprocessable, "Failed to apply field suggestion: #{result.message}"
          end

          ::Issues::PendingFieldSuggestion.update_state(
            repository_id: repository.id,
            issue_id: issue.id,
            issue_field_id: T.must(issue_field.id),
            state: ::Issues::PendingFieldSuggestion::STATE_APPLIED,
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

      def build_field_attribute(issue_field, value)
        issue_field.build_value_attributes(value)
      rescue ::IssueField::InvalidValueError => e
        raise Errors::Unprocessable, "Failed to apply field suggestion: #{e.message}"
      end

      def intent_migration_enabled?
        FeatureFlag.vexi.enabled?(:issues_intent_model_migration, default: false)
      end

      # Persists the suggester's rationale as an EventAnnotation tied to the
      # newly-created LabeledEvent so the recent-agent-activity panel can
      # render an "applied" row for it. Reads from the legacy suggestion hash.
      def store_label_rationale(issue:, repository:, label:, suggestion:, actor:)
        rationale_text = suggestion["rationale"]
        return if rationale_text.blank?
        return unless FeatureFlag.vexi.enabled?(:update_issue_rationale, actor, repository.owner, repository, default: false)

        label_event = issue.events
          .joins(:issue_event_detail)
          .where(event: "labeled", actor_id: context[:viewer].id, issue_event_details: { label_id: label.id })
          .order(id: :desc).first
        return unless label_event

        confidence = pending_suggestion_confidence(suggestion, repository: repository, actor: actor)

        ::Issues::EventAnnotation.create(
          repository_id: repository.id,
          issue_id: issue.id,
          issue_event_id: label_event.id,
          rationale: rationale_text,
          actor_id: actor.id,
          confidence: confidence,
          action: Issues::EventAnnotation::KIND_LABEL,
        )
      rescue => e
        GitHub.logger.error("issues.apply_pending_issue_suggestions.label_rationale_store_failed", {
          "code.namespace" => "Platform::Mutations::ApplyPendingIssueSuggestions",
          "issue_id" => issue.id,
          "repository_id" => repository.id,
          "label_id" => label.id,
          "error" => e.message,
        })
      end

      # As `store_label_rationale`, but reads rationale + confidence from
      # the UpdateIntent record and takes the LabeledEvent as input rather
      # than re-querying for it.
      def store_intent_label_rationale(issue:, repository:, label_event:, intent:, actor:)
        return if intent.rationale.blank?
        return unless label_event
        return unless FeatureFlag.vexi.enabled?(:update_issue_rationale, actor, repository.owner, repository, default: false)

        confidence = intent.confidence if FeatureFlag.vexi.enabled?(:update_issue_confidence, actor, repository.owner, repository, default: false)

        # Only write the KV annotation for timeline display — update_state
        # handles the DB row transition (pending → approved + issue_event_id).
        ::Issues::EventAnnotation.store_kv_annotation(
          repository_id: repository.id,
          issue_id: issue.id,
          issue_event_id: label_event.id,
          rationale: intent.rationale,
          actor_id: actor.id,
          confidence: confidence,
        )
      rescue => e
        GitHub.logger.error("issues.apply_pending_issue_suggestions.intent_label_rationale_store_failed", {
          "code.namespace" => "Platform::Mutations::ApplyPendingIssueSuggestions",
          "issue_id" => issue.id,
          "repository_id" => repository.id,
          "intent_id" => intent.id,
          "error" => e.message,
        })
      end

      # Persists the suggester's rationale as a pending annotation so
      # HydroIssueFieldTimelineEventsJob can consume it when it creates the
      # IssueFieldAddedEvent / IssueFieldChangedEvent. Reads from the legacy
      # suggestion hash.
      def store_field_pending_rationale(issue:, repository:, issue_field:, suggestion:, actor:)
        rationale_text = suggestion["rationale"]
        return if rationale_text.blank?
        return unless FeatureFlag.vexi.enabled?(:update_issue_rationale, actor, repository.owner, repository, default: false)

        confidence = pending_suggestion_confidence(suggestion, repository: repository, actor: actor)

        ::Issues::EventAnnotation.store_pending(
          repository_id: repository.id,
          issue_id: issue.id,
          kind: ::Issues::EventAnnotation::KIND_FIELD,
          target_id: T.must(issue_field.id),
          rationale: rationale_text,
          actor_id: actor.id,
          confidence: confidence,
        )
      rescue => e
        GitHub.logger.error("issues.apply_pending_issue_suggestions.field_rationale_store_failed", {
          "code.namespace" => "Platform::Mutations::ApplyPendingIssueSuggestions",
          "issue_id" => issue.id,
          "repository_id" => repository.id,
          "issue_field_id" => issue_field.id,
          "error" => e.message,
        })
      end

      # As `store_field_pending_rationale`, but reads rationale + confidence
      # from the UpdateIntent record.
      def store_intent_field_pending_rationale(issue:, repository:, issue_field:, intent:, actor:)
        return if intent.rationale.blank?
        return unless FeatureFlag.vexi.enabled?(:update_issue_rationale, actor, repository.owner, repository, default: false)

        confidence = intent.confidence if FeatureFlag.vexi.enabled?(:update_issue_confidence, actor, repository.owner, repository, default: false)

        ::Issues::EventAnnotation.store_pending(
          repository_id: repository.id,
          issue_id: issue.id,
          kind: ::Issues::EventAnnotation::KIND_FIELD,
          target_id: T.must(issue_field.id),
          rationale: intent.rationale,
          actor_id: actor.id,
          confidence: confidence,
        )
      rescue => e
        GitHub.logger.error("issues.apply_pending_issue_suggestions.intent_field_rationale_store_failed", {
          "code.namespace" => "Platform::Mutations::ApplyPendingIssueSuggestions",
          "issue_id" => issue.id,
          "repository_id" => repository.id,
          "intent_id" => intent.id,
          "error" => e.message,
        })
      end

      # Persists the suggester's rationale as a pending annotation so
      # HydroIssueTypeTimelineEventsJob can consume it when it creates the
      # IssueTypeAddedEvent / IssueTypeChangedEvent. Reads from the legacy
      # suggestion hash.
      def store_type_pending_rationale(issue:, repository:, issue_type:, suggestion:, actor:)
        rationale_text = suggestion["rationale"]
        return if rationale_text.blank?
        return unless FeatureFlag.vexi.enabled?(:update_issue_rationale, actor, repository.owner, repository, default: false)

        confidence = pending_suggestion_confidence(suggestion, repository: repository, actor: actor)

        ::Issues::EventAnnotation.store_pending(
          repository_id: repository.id,
          issue_id: issue.id,
          kind: ::Issues::EventAnnotation::KIND_TYPE,
          target_id: T.must(issue_type.id),
          rationale: rationale_text,
          actor_id: actor.id,
          confidence: confidence,
        )
      rescue => e
        GitHub.logger.error("issues.apply_pending_issue_suggestions.type_rationale_store_failed", {
          "code.namespace" => "Platform::Mutations::ApplyPendingIssueSuggestions",
          "issue_id" => issue.id,
          "repository_id" => repository.id,
          "issue_type_id" => issue_type.id,
          "error" => e.message,
        })
      end

      # As `store_type_pending_rationale`, but reads rationale + confidence
      # from the UpdateIntent record.
      def store_intent_type_pending_rationale(issue:, repository:, issue_type:, intent:, actor:)
        return if intent.rationale.blank?
        return unless FeatureFlag.vexi.enabled?(:update_issue_rationale, actor, repository.owner, repository, default: false)

        confidence = intent.confidence if FeatureFlag.vexi.enabled?(:update_issue_confidence, actor, repository.owner, repository, default: false)

        ::Issues::EventAnnotation.store_pending(
          repository_id: repository.id,
          issue_id: issue.id,
          kind: ::Issues::EventAnnotation::KIND_TYPE,
          target_id: T.must(issue_type.id),
          rationale: intent.rationale,
          actor_id: actor.id,
          confidence: confidence,
        )
      rescue => e
        GitHub.logger.error("issues.apply_pending_issue_suggestions.intent_type_rationale_store_failed", {
          "code.namespace" => "Platform::Mutations::ApplyPendingIssueSuggestions",
          "issue_id" => issue.id,
          "repository_id" => repository.id,
          "intent_id" => intent.id,
          "error" => e.message,
        })
      end

      # Returns the suggestion's stored confidence level when the
      # `:update_issue_confidence` flag is enabled for this repo/actor, nil otherwise.
      def pending_suggestion_confidence(suggestion, repository:, actor:)
        return nil unless FeatureFlag.vexi.enabled?(:update_issue_confidence, actor, repository.owner, repository, default: false)

        ::Issues::ConfidenceThreshold::Level.try_deserialize(suggestion["confidence"])
      end
    end
  end
end
