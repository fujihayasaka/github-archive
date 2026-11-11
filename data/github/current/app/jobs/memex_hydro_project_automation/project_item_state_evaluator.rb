# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

module MemexHydroProjectAutomation
  module ProjectItemStateEvaluator
    TriggerConfig = T.type_alias do
      {
        # The action type that should be used when looking up workflows in MemexProjectWorkflowAction
        # defined in MemexProjectWorkflow
        action: Symbol,
        # A lambda that receives (item: MemexProjectItem, actor: User/Organization/Business) and returns
        # true if this trigger should fire for the given item's current state
        validator: T.proc.params(item: T.untyped, actor: T.untyped).returns(T::Boolean),
        # Array of content types this trigger applies to. If nil, applies to all types.
        content_types: T.nilable(T::Array[String]),
        # Whether this trigger is enabled for item add
        enabled_for_item_addition: T::Boolean
      }
    end

    TRIGGER_CONFIGS = T.let({
      item_added: {
        action: :set_field,
        validator: ->(_item, _actor) { true },
        content_types: nil, # applies to all content types
        enabled_for_item_addition: true
      },
      closed: {
        action: :set_field,
        validator: ->(item, _actor) {
          item.state == "closed" &&
            (
              item.content_type == "Issue" ||
              (item.content_type == "PullRequest" && item.content.try(:merged_at).nil?)
            )
        },
        content_types: %w[Issue PullRequest],
        enabled_for_item_addition: true
      },
      merged: {
        action: :set_field,
        validator: ->(item, actor) {
          return false unless item.content_type == "PullRequest" && item.state == "closed"
          return false unless FeatureFlag.vexi.enabled?(:memex_additional_workflows_by_trigger, actor, default: false)

          item.content.try(:merged_at)&.present? || false
        },
        content_types: ["PullRequest"],
        enabled_for_item_addition: true
      },
      pr_connected: {
        action: :set_field,
        validator: ->(item, actor) {
          return false unless FeatureFlag.vexi.enabled?(:memex_linked_pr_progress_workflow, actor, default: false)
          item.state == "open" &&
            item.content_type == "Issue" &&
            item.content.try(:close_issue_references).present? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        },
        content_types: ["Issue"],
        enabled_for_item_addition: true
      },
      review_approved: {
        action: :set_field,
        validator: ->(item, actor) {
          return false unless item.content_type == "PullRequest"
          return false unless FeatureFlag.vexi.enabled?(:memex_additional_workflows_by_trigger, actor, default: false)

          policy_decision = item.content.try(:merge_state)&.pull_request_review_policy_decision
          policy_decision&.approved? || false
        },
        content_types: ["PullRequest"],
        enabled_for_item_addition: true
      },
      review_changes_requested: {
        action: :set_field,
        validator: ->(item, actor) {
          return false unless item.content_type == "PullRequest"
          return false unless FeatureFlag.vexi.enabled?(:memex_additional_workflows_by_trigger, actor, default: false)

          policy_decision = item.content.try(:merge_state)&.pull_request_review_policy_decision
          policy_decision&.changes_requested? || false
        },
        content_types: ["PullRequest"],
        enabled_for_item_addition: true
      },
      sub_issues: {
        action: :add_project_item,
        validator: ->(item, _actor) {
          item.content.try(:sub_issues).present? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        },
        content_types: ["Issue"],
        enabled_for_item_addition: true
      },
      # Triggers that are irrelevant when adding an item to a board:
      reopened: {
        action: :set_field,
        validator: ->(_item, _actor) { false },
        content_types: nil,
        enabled_for_item_addition: false
      },
      query_matched: {
        action: :set_field,
        validator: ->(_item, _actor) { false },
        content_types: nil,
        enabled_for_item_addition: false
      },
      project_item_column_update: {
        action: :set_field,
        validator: ->(_item, _actor) { false },
        content_types: nil,
        enabled_for_item_addition: false
      }
    }.freeze, T::Hash[Symbol, TriggerConfig])

    # Pre-grouped trigger configs by content type for performance optimization
    # This avoids running validators for incompatible content types (e.g., PR validators on Issues)
    issue_trigger_configs = TRIGGER_CONFIGS.select do |_, config|
      config[:enabled_for_item_addition] &&
      (config[:content_types].nil? || config[:content_types].include?("Issue"))
    end
    ISSUE_TRIGGERS = T.let(
      issue_trigger_configs.freeze,
      T::Hash[Symbol, TriggerConfig]
    )

    pull_request_trigger_configs = TRIGGER_CONFIGS.select do |_, config|
      config[:enabled_for_item_addition] &&
      (config[:content_types].nil? || config[:content_types].include?("PullRequest"))
    end
    PULL_REQUEST_TRIGGERS = T.let(
      pull_request_trigger_configs.freeze,
      T::Hash[Symbol, TriggerConfig]
    )

    draft_issue_trigger_configs = TRIGGER_CONFIGS.select do |_, config|
      config[:enabled_for_item_addition] &&
      config[:content_types].nil?
    end
    DRAFT_ISSUE_TRIGGERS = T.let(
      draft_issue_trigger_configs.freeze,
      T::Hash[Symbol, TriggerConfig]
    )

    # Universal triggers for unknown/fallback content types
    # Pre-computed to avoid runtime filtering
    universal_trigger_configs = TRIGGER_CONFIGS.select do |_, config|
      config[:enabled_for_item_addition] &&
      config[:content_types].nil?
    end
    UNIVERSAL_TRIGGERS = T.let(
      universal_trigger_configs.freeze,
      T::Hash[Symbol, TriggerConfig]
    )

    # Evaluates the current state of project items when added to determine which workflows should run.
    #
    # For each item, the method:
    # 1. Filters to only triggers that have enabled workflows for the project (performance optimization)
    # 2. Further filters to triggers compatible with the item's content type
    # 3. Runs each trigger's validator to check if the item's current state matches
    # 4. Returns matched [trigger_type, action_type] pairs
    #
    # Examples:
    # - Closed issue with enabled workflows: [[:item_added, :set_field], [:closed, :set_field]]
    # - Open issue with sub-issues: [[:item_added, :set_field], [:sub_issues, :add_project_item]]
    # - Merged PR (when feature flag enabled): [[:item_added, :set_field], [:merged, :set_field]]
    # - Draft issue: [[:item_added, :set_field]] (only universal triggers apply)
    #
    # NOTE: Requires the including class to implement `enabled_workflows_for_projects(project_ids)`.
    #
    # @param project_items [Array<MemexProjectItem>] Project items to evaluate
    # @param actor [User, Organization, Business] Actor for feature flag checks
    # @return [Hash<MemexProjectItem, Array<Array<Symbol, Symbol>>>] Hash mapping each item to its [trigger_type, action_type] pairs
    sig do
      params(
        project_items: T::Array[MemexProjectItem],
        actor: T.any(User, Organization, Business)
      ).returns(T::Hash[MemexProjectItem, T::Array[[Symbol, Symbol]]])
    end
    def evaluate_workflows_for_added_items(project_items, actor)
      return {} if project_items.empty?

      # Fetch enabled workflows for optimization
      project_ids = project_items.map(&:memex_project_id).uniq
      enabled_workflows = T.unsafe(self).enabled_workflows_for_projects(project_ids)
      workflows_by_trigger = enabled_workflows.group_by { |w| w.trigger_type.to_sym }

      # Preload associations to reduce N+1 queries
      preload_associations(project_items)

      # Evaluate each item
      project_items.each_with_object({}) do |project_item, result|
        pairs = []

        # Select the appropriate pre-grouped trigger configs based on content type
        # This optimization ensures we only run validators that are compatible with the content type
        relevant_triggers = case project_item.content_type
        when "Issue"
          ISSUE_TRIGGERS
        when "PullRequest"
          PULL_REQUEST_TRIGGERS
        when "DraftIssue"
          DRAFT_ISSUE_TRIGGERS
        else
          # Fallback to universal triggers for unknown content types
          UNIVERSAL_TRIGGERS
        end

        # Map DraftIssue to Issue for workflow compatibility when checking enabled workflows
        workflow_content_type = project_item.content_type == "DraftIssue" ? "Issue" : project_item.content_type

        # Only evaluate triggers that both:
        # 1. Are compatible with the content type (via relevant_triggers)
        # 2. Have enabled workflows for this project (via workflows_by_trigger)
        relevant_triggers.each do |trigger_type, config|
          # Skip if no workflows are enabled for this trigger type
          workflows = workflows_by_trigger[trigger_type]
          next unless workflows

          # Skip if no workflows match this content type
          next unless workflows.any? { |w| w.content_types.nil? || w.content_types&.include?(workflow_content_type) }

          # Run the validator to check if this trigger should fire
          next unless config[:validator].call(project_item, actor)

          pairs << [trigger_type, config[:action]]
        end

        result[project_item] = pairs
      end
    end

    private

    sig { params(project_items: T::Array[MemexProjectItem]).void }
    def preload_associations(project_items)
      GitHub::PrefillAssociations.prefill_associations(project_items, [:content])

      issue_items = project_items.select { |item| item.content_type == "Issue" }

      if issue_items.any?
        issues = issue_items.map(&:content).compact
        GitHub::PrefillAssociations.prefill_associations(issues, [:sub_issues, :close_issue_references]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end
  end
end
