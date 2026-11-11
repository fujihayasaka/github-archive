# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    # Shared helpers for GraphQL mutations that accept the rationale + suggest
    # shape gated behind the `:update_issue_suggestions` feature flag. The flag
    # is enforced at two levels:
    #   - Schema visibility: `feature_flag:` on the input/argument (viewer-scoped).
    #   - Runtime: re-evaluated against the issue's repository, since rollout
    #     is repo-scoped. When the runtime check fails, callers should
    #     silently drop `suggest` and `rationale` rather than failing the
    #     whole mutation — those fields may have been schema-visible to the
    #     viewer but the issue's repo isn't part of the rollout.
    module IssueSuggestions
      # Hard-block flagged accounts from creating suggestion or rationale
      # records on issues. Mirrors the REST guard in
      # `Api::Issues#ensure_actor_not_flagged_for_suggestions!`.
      #
      # Suggestion records (`Pending*Suggestion`, `Issues::UpdateIntent`,
      # `Issues::EventAnnotation`) are not `Spammable`, and the triage agent's
      # bot-attributed comment bypasses `Spam::Spammable#user_hidden`. Without
      # this guard a flagged account — or its agent operating on a flagged
      # account's repo, or an App owned by a flagged account — could persist
      # user-supplied text outside the usual content-hidden filtering.
      # Callers should invoke this only on the suggestion / rationale path so
      # plain field/label/type updates from spammy users keep their existing
      # behavior.
      def ensure_actor_not_flagged_for_suggestions!(repository)
        return unless GitHub.spamminess_check_enabled?
        return unless repository

        viewer = @context[:viewer]
        owner = repository.owner
        integration = @context[:integration]

        reason =
          if viewer&.spammy?
            "current_user"
          elsif owner&.spammy?
            "repo_owner"
          elsif integration&.owner&.spammy?
            "app_owner"
          end
        return unless reason

        GitHub.dogstats.increment(
          "graphql.issues.suggestions.spammy_actor_blocked",
          tags: ["reason:#{reason}"],
        )
        Kernel.raise Errors::Forbidden.new(
          "Suggestions and rationale are disabled for accounts that have been flagged.",
        )
      end

      # True when any `LabelUpdateInput` entry carries `suggest: true` or a
      # non-blank `rationale`. Used to gate the spammy-actor check so it only
      # fires on the suggestion / rationale path.
      def label_inputs_carry_suggest_or_rationale?(label_inputs)
        return false if label_inputs.blank?
        label_inputs.any? { |li| !!li[:suggest] || li[:rationale].presence }
      end

      # True when an `IssueTypeUpdateInput` carries `suggest: true` or a
      # non-blank `rationale`.
      def type_input_carries_suggest_or_rationale?(type_input)
        return false if type_input.nil?
        !!type_input[:suggest] || type_input[:rationale].presence
      end

      # True when any `IssueFieldCreateOrUpdateInput` entry (single or list)
      # carries `suggest: true` or a non-blank `rationale`. The argument is
      # struct-shaped (not a Hash) for these inputs, so access uses methods.
      def field_inputs_carry_suggest_or_rationale?(field_inputs)
        return false if field_inputs.nil?
        Kernel.Array(field_inputs).any? { |fi| !!fi.suggest || fi.rationale.presence }
      end

      # True when the `:update_issue_suggestions` feature flag is enabled for
      # the issue's repository.
      def update_issue_suggestions_enabled?(repository)
        FeatureFlag.vexi.enabled?(:update_issue_suggestions, @context[:viewer], repository.owner, repository, default: false)
      end

      # True when the `:update_issue_confidence` feature flag is enabled for
      # the issue's repository. Mirrors the REST API gate in `Api::Issues`.
      def update_issue_confidence_enabled?(repository)
        FeatureFlag.vexi.enabled?(:update_issue_confidence, @context[:viewer], repository.owner, repository, default: false)
      end

      # Wrap `Pending*Suggestion.create(...)` and translate the domain's
      # LimitExceeded / DuplicateSuggestion errors into a user-facing
      # Unprocessable error. Sorbet rejects dynamic constant references in
      # `rescue`, so all known suggestion error classes are listed explicitly.
      def create_pending_suggestion!(klass, **attrs)
        klass.create(**attrs)
      rescue Issues::PendingTypeSuggestion::LimitExceeded,
             Issues::PendingTypeSuggestion::DuplicateSuggestion,
             Issues::PendingLabelSuggestion::LimitExceeded,
             Issues::PendingLabelSuggestion::DuplicateSuggestion,
             Issues::PendingFieldSuggestion::LimitExceeded,
             Issues::PendingFieldSuggestion::DuplicateSuggestion => e
        Kernel.raise Errors::Unprocessable.new(e.message)
      end

      # Partition a list of `LabelUpdateInput` values into applied labels,
      # suggested inputs, and a rationale map for the applied set. When the
      # repo's FF is off, suggestions and rationales are silently dropped (the
      # input was schema-visible to the viewer but rollout is repo-scoped).
      #
      # Returns `[applied_labels, suggested_inputs, label_rationales]`.
      def partition_label_suggestion_inputs(repository, label_inputs)
        suggested_inputs, applied_inputs = label_inputs.partition { |li| !!li[:suggest] }
        suggestions_enabled = update_issue_suggestions_enabled?(repository)
        unless suggestions_enabled
          suggested_inputs = []
        end

        applied_labels = applied_inputs.map { |li| li[:label] }

        label_rationales = T.let({}, T::Hash[Integer, String])
        label_confidences = T.let({}, T::Hash[Integer, Issues::ConfidenceThreshold::Level])
        if suggestions_enabled
          confidence_enabled = update_issue_confidence_enabled?(repository)
          applied_inputs.each do |li|
            label_id = T.must(li[:label].id)
            text = li[:rationale].presence
            label_rationales[label_id] = text if text
            if confidence_enabled
              confidence = resolve_confidence_level(li[:confidence])
              label_confidences[label_id] = confidence if confidence
            end
          end
        end

        [applied_labels, suggested_inputs, label_rationales, label_confidences]
      end

      # Persist a list of `Issues::PendingLabelSuggestion`s (one per
      # `LabelUpdateInput`) for the given issue. Errors raised by the domain
      # bubble up as `Errors::Unprocessable` via `create_pending_suggestion!`.
      # Per-input `confidence` is persisted on the suggestion when the
      # `:update_issue_confidence` FF is enabled for the issue's repository,
      # mirroring the gate applied to applied-label confidence.
      def persist_label_suggestions!(repository:, issue:, suggested_inputs:)
        confidence_enabled = update_issue_confidence_enabled?(repository)
        suggested_inputs.each do |li|
          create_pending_suggestion!(
            Issues::PendingLabelSuggestion,
            repository_id: repository.id,
            issue_id: issue.id,
            label_id: T.must(li[:label].id),
            rationale: li[:rationale].to_s,
            actor_id: @context[:viewer].id,
            confidence: confidence_enabled ? resolve_confidence_level(li[:confidence]) : nil,
          )
        end
      end

      # `labeled` IssueEvents are created synchronously during the
      # add/replace_labels operation, so the rationale is attached directly to
      # the most recent matching event for this actor + label. Mirrors
      # `Api::Issues#store_rationale_annotations`.
      def store_label_rationale_annotations(issue:, repository:, actor:, label_rationales:, label_confidences: {})
        return if label_rationales.empty?

        label_rationales.each do |label_id, rationale_text|
          next if rationale_text.blank?

          label_event = issue.events
            .joins(:issue_event_detail)
            .where(event: "labeled", actor_id: actor.id, issue_event_details: { label_id: label_id })
            .order(id: :desc).first
          next unless label_event

          Issues::EventAnnotation.create(
            repository_id: repository.id,
            issue_id: issue.id,
            issue_event_id: label_event.id,
            rationale: rationale_text,
            actor_id: actor.id,
            confidence: label_confidences[label_id],
            action: Issues::EventAnnotation::KIND_LABEL,
          )
        rescue => e
          GitHub.logger.error("issues.label_rationale_store_failed", {
            "code.namespace" => "Platform::Helpers::IssueSuggestions",
            "repository_id" => repository.id,
            "issue_id" => issue.id,
            "label_id" => label_id,
            "error.type" => e.class.name,
            "error.message" => e.message,
          })
        end
      end

      # Persist an `Issues::PendingFieldSuggestion` for one
      # `IssueFieldCreateOrUpdateInput`. The field's global ID is resolved to
      # an integer here so callers don't need to. Errors raised by the domain
      # bubble up as `Errors::Unprocessable` via `create_pending_suggestion!`.
      # `confidence` is optional and should be passed in already gated by the
      # `:update_issue_confidence` FF (callers strip it when the flag is off).
      def persist_field_suggestion!(repository:, issue:, issue_field:, confidence: nil)
        field_id = Platform::Helpers::NodeIdentification.from_global_id(issue_field.field_id)[1].to_i
        create_pending_suggestion!(
          Issues::PendingFieldSuggestion,
          repository_id: repository.id,
          issue_id: issue.id,
          issue_field_id: field_id,
          value: extract_field_value(issue_field),
          rationale: issue_field.rationale.to_s,
          actor_id: @context[:viewer].id,
          confidence: confidence,
        )
      end

      # Extract whatever value the caller supplied on an
      # `IssueFieldCreateOrUpdateInput`, in the untyped shape
      # `Issues::PendingFieldSuggestion` stores for the REST API path.
      # Single-select / multi-select option IDs arrive as GraphQL global Relay
      # IDs, but the pending-suggestion store persists option *names* — both
      # so the value renders as the human-readable option name in UIs that
      # display `pending["value"]` directly, and so that the apply path
      # (`IssueField#build_value_attributes`) can resolve it back to the
      # option, matching what the REST suggestion endpoint persists.
      def extract_field_value(issue_field)
        return nil if issue_field.delete
        return issue_field.text_value if issue_field.text_value
        return issue_field.date_value if issue_field.date_value
        if issue_field.single_select_option_id
          return resolve_option_name!(issue_field.single_select_option_id)
        end
        if issue_field.multi_select_option_ids.present?
          return issue_field.multi_select_option_ids.map { |gid| resolve_option_name!(gid) }
        end
        return issue_field.number_value if issue_field.number_value

        nil
      end

      # Resolve a single-select / multi-select option's GraphQL global Relay
      # ID to its `name`. Raises `Errors::Unprocessable` when the ID can't be
      # decoded or the option is missing, so we never persist a stale or
      # garbage value into the suggestion store.
      def resolve_option_name!(global_id)
        option_id = Platform::Helpers::NodeIdentification.from_global_id(global_id)[1].to_i
        option = ::IssueFieldOption.find_by(id: option_id) if option_id.positive?
        unless option
          Kernel.raise Errors::Unprocessable.new("Issue field option not found: #{global_id}")
        end
        option.name
      end

      # Field timeline events are created asynchronously via Hydro, so the
      # rationale is stored as a pending annotation that the consumer job
      # attaches when it creates the event. Mirrors the REST behavior in
      # `Api::Issues#store_rationale_annotations`.
      def store_field_rationale_annotation(issue:, repository:, actor:, field_id:, rationale:, confidence: nil)
        return if rationale.blank?

        Issues::EventAnnotation.store_pending(
          repository_id: repository.id,
          issue_id: issue.id,
          kind: Issues::EventAnnotation::KIND_FIELD,
          target_id: field_id,
          rationale: rationale,
          actor_id: actor.id,
          confidence: confidence,
        )
      rescue => e
        GitHub.logger.error("issues.field_rationale_store_failed", {
          "code.namespace" => "Platform::Helpers::IssueSuggestions",
          "repository_id" => repository.id,
          "issue_id" => issue.id,
          "field_id" => field_id,
          "error.type" => e.class.name,
          "error.message" => e.message,
        })
      end

      # Persist an `Issues::PendingTypeSuggestion` for an issue. Errors raised
      # by the domain bubble up as `Errors::Unprocessable` via
      # `create_pending_suggestion!`. `confidence` is optional and should be
      # passed in already gated by the `:update_issue_confidence` FF (callers
      # strip it when the flag is off).
      def persist_type_suggestion!(repository:, issue:, issue_type_id:, rationale:, confidence: nil)
        create_pending_suggestion!(
          Issues::PendingTypeSuggestion,
          repository_id: repository.id,
          issue_id: issue.id,
          issue_type_id: issue_type_id,
          rationale: rationale.to_s,
          actor_id: @context[:viewer].id,
          confidence: confidence,
        )
      end

      # Persist a rationale annotation for an issue type change. The actual
      # `typed`/`untyped` IssueEvent is created asynchronously via Hydro, so
      # this stores a pending annotation that the consumer job attaches when
      # it creates the event. No-op if the issue has no current type or the
      # rationale is blank. Mirrors the REST behavior in
      # `Api::Issues#store_rationale_annotations`.
      def store_issue_type_rationale_annotation(issue:, repository:, actor:, rationale:, confidence: nil)
        return if rationale.blank?
        return unless issue.issue_type_id

        Issues::EventAnnotation.store_pending(
          repository_id: repository.id,
          issue_id: issue.id,
          kind: Issues::EventAnnotation::KIND_TYPE,
          target_id: issue.issue_type_id,
          rationale: rationale,
          actor_id: actor.id,
          confidence: confidence,
        )
      rescue => e
        GitHub.logger.error("issues.issue_type_rationale_store_failed", {
          "code.namespace" => "Platform::Helpers::IssueSuggestions",
          "repository_id" => repository.id,
          "issue_id" => issue.id,
          "error.type" => e.class.name,
          "error.message" => e.message,
        })
      end

      # Convert a GraphQL enum string (e.g. "HIGH") to an
      # Issues::ConfidenceThreshold::Level instance. Returns nil for blank input.
      def resolve_confidence_level(value)
        return nil if value.blank?

        Issues::ConfidenceThreshold::Level.try_deserialize(value)
      end
    end
  end
end
