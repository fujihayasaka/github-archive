# typed: false
# frozen_string_literal: true

class ProjectWorkflow < ApplicationRecord::Domain::Projects
  include GitHub::Relay::GlobalIdentification
  include Instrumentation::Model

  # Let's us skip the instrumentation when running V1 -> V2 transformations
  # so we don't end up with confusing audit log entries
  # leave this in place for now as it will be used by the transition and run on
  # enterprise migrations
  attr_accessor :skip_instrument_creation_callback

  ISSUE_CLOSED_TRIGGER = "issue_closed".freeze
  ISSUE_PENDING_CARD_ADDED_TRIGGER = "issue_pending_card_added".freeze
  ISSUE_REOPENED_TRIGGER = "issue_reopened".freeze
  PR_APPROVED_TRIGGER = "pr_approved".freeze
  PR_CLOSED_NOT_MERGED_TRIGGER = "pr_closed_not_merged".freeze
  PR_MERGED_TRIGGER = "pr_merged".freeze
  PR_PENDING_APPROVAL_TRIGGER = "pr_pending_approval".freeze
  PR_PENDING_CARD_ADDED_TRIGGER = "pr_pending_card_added".freeze
  PR_REOPENED_TRIGGER = "pr_reopened".freeze

  # This uses the *TRIGGER constants declared above, so must appear after those declarations.
  include ProjectWorkflow::MigrationDependency

  # Do not store this value, used to trigger a reevaluation of
  # of whether a PR is approved or pending approval and run
  # appropriate workflow
  REVIEW_DISMISSED_TRIGGER = "review_dismissed".freeze

  EXTERNAL_TRIGGERS = [
    ISSUE_PENDING_CARD_ADDED_TRIGGER,
    ISSUE_CLOSED_TRIGGER,
    ISSUE_REOPENED_TRIGGER,
    PR_APPROVED_TRIGGER,
    PR_CLOSED_NOT_MERGED_TRIGGER,
    PR_MERGED_TRIGGER,
    PR_PENDING_APPROVAL_TRIGGER,
    PR_PENDING_CARD_ADDED_TRIGGER,
    PR_REOPENED_TRIGGER,
    REVIEW_DISMISSED_TRIGGER,
  ].freeze

  PR_ONLY_TRIGGERS = [
    PR_APPROVED_TRIGGER,
    PR_CLOSED_NOT_MERGED_TRIGGER,
    PR_MERGED_TRIGGER,
    PR_PENDING_APPROVAL_TRIGGER,
    PR_PENDING_CARD_ADDED_TRIGGER,
    PR_REOPENED_TRIGGER,
    REVIEW_DISMISSED_TRIGGER,
  ].freeze

  PENDING_CARD_TRIGGERS = [
    ISSUE_PENDING_CARD_ADDED_TRIGGER,
    PR_PENDING_CARD_ADDED_TRIGGER,
  ].freeze

  REOPENED_TRIGGERS = [
    ISSUE_REOPENED_TRIGGER,
    PR_REOPENED_TRIGGER,
  ].freeze

  REVIEW_TRIGGERS = [
    PR_APPROVED_TRIGGER,
    PR_PENDING_APPROVAL_TRIGGER,
    REVIEW_DISMISSED_TRIGGER,
  ].freeze

  DONE_TRIGGERS = [
    ISSUE_CLOSED_TRIGGER,
    PR_MERGED_TRIGGER,
    PR_CLOSED_NOT_MERGED_TRIGGER,
  ].freeze

  belongs_to :project
  belongs_to :project_column
  belongs_to :creator, class_name: "User"
  belongs_to :last_updater, class_name: "User"

  has_many :actions, class_name: "ProjectWorkflowAction", dependent: :destroy

  validates :trigger_type, inclusion: { in: EXTERNAL_TRIGGERS }
  validates :creator, presence: true
  validates :project, presence: true
  validates :project_column, presence: true

  before_update :set_updater
  after_commit :instrument_creation, :track_project_workflow_creation, on: :create, if: proc {
    !skip_instrument_creation_callback
  }
  after_commit :instrument_update, on: :update
  after_commit :instrument_deletion, :track_project_workflow_deletion, on: :destroy

  class MissingIssueObject < StandardError; end

  # Public: Retrieves existing workflow for the trigger type or
  #         builds a new one if none exist.
  #         This should only run on a Project scope
  #
  # creator - user that will be used for a new workflow if needed
  # trigger_type - trigger type used for the workflow
  #
  # Returns a ProjectWorkflow
  def self.set_workflow(trigger_type:, column:, creator: nil)
    return unless EXTERNAL_TRIGGERS.include?(trigger_type)
    workflow = where(trigger_type: trigger_type).first

    unless workflow.present?
      workflow = new(trigger_type: trigger_type, creator: creator, project_column: column)
      return unless workflow.save
    end

    unless workflow.set_transition_action(column: column, creator: creator)
      workflow.destroy
      return
    end
    workflow
  end

  # Public: Set the action that will cause a transition into a column.
  #
  # column   - The column to transition a card into when triggering event occurs.
  # creator  - The User who is creating the action.
  #
  # Returns a Boolean
  def set_transition_action(column:, creator:)
    unless column.project_id == project_id
      raise ArgumentError, "Column does not belong to this project"
    end

    action = actions.locate(:transition_to_column)

    unless action.present?
      action = actions.create(action_type: ProjectWorkflowAction::TRANSITION_TO_COLUMN, creator: creator, project: project)
    end

    return false unless action.persisted?

    update_attribute(:project_column_id, column.id)
  end

  # Internal: Find all the cards that should have been moved by this workflow
  #
  # If a project is closed, workflows don't run. This method works out which
  # cards would have been moved had the workflow been running during the
  # specified time period, so that they can be resynced.
  #
  # as_of - The Time to stop searching to (inclusive)
  #
  # Example
  #   workflow.cards_needing_resync(as_of: Time.current)
  #   => [ProjectCard, ProjectCard, ...]
  #
  # Returns an ActiveRecord::Relation containing the matching cards
  def cards_needing_resync(as_of:)
    card_scope = project.cards
    issue_scope = if PR_ONLY_TRIGGERS.include?(trigger_type)
      Issue.with_pull_requests
    else
      Issue.without_pull_requests
    end

    if PENDING_CARD_TRIGGERS.include?(trigger_type)
      return card_scope.where("column_id IS NULL").for_issues(scope: issue_scope)
    end

    card_scope = card_scope.not_archived.where.not(column_id: project_column_id)
    sanitized_as_of = Time.parse as_of.to_s

    issue_scope = case trigger_type
    when ISSUE_CLOSED_TRIGGER
      issue_scope.where(issues: { state: "closed" }).
        where("issues.closed_at <= ?", sanitized_as_of)
    when PR_MERGED_TRIGGER
      issue_scope.joins("INNER JOIN pull_requests ON issues.pull_request_id = pull_requests.id").
        where("pull_requests.merged_at <= ?", sanitized_as_of)
    when ISSUE_REOPENED_TRIGGER, PR_REOPENED_TRIGGER
      # Note: for PRs we're just using the
      # underlying Issue for checking time, state, etc.
      issue_scope.joins("INNER JOIN issue_events ON issues.id = issue_events.issue_id AND issue_events.event = 'reopened'").
        where(issues: { state: "open" }).
        where("issue_events.created_at <= ?", sanitized_as_of).
        distinct
    when PR_CLOSED_NOT_MERGED_TRIGGER
      issue_scope.joins("INNER JOIN pull_requests ON issues.pull_request_id = pull_requests.id").
        where(pull_requests: { merged_at: nil }, issues: { state: "closed" }).
        where("issues.closed_at <= ?", sanitized_as_of)
    when PR_APPROVED_TRIGGER
      issue_scope.joins("INNER JOIN pull_request_reviews ON issues.pull_request_id = pull_request_reviews.pull_request_id").
        where("pull_request_reviews.submitted_at <= ?", sanitized_as_of).
        where(pull_request_reviews: { state: PullRequestReview.state_value(:approved) })
    when PR_PENDING_APPROVAL_TRIGGER
      issue_scope.joins("INNER JOIN pull_request_reviews ON issues.pull_request_id = pull_request_reviews.pull_request_id").
        where("pull_request_reviews.submitted_at <= ?", sanitized_as_of).
        where(pull_request_reviews: {
          state: [
            PullRequestReview.state_value(:changes_requested),
            PullRequestReview.state_value(:dismissed),
          ],
        })
    else
      Issue.none
    end

    card_scope.for_issues(scope: issue_scope)
  end

  # Internal: Apply this workflow to cards that it should have caught while switched off
  #
  # actor - The User triggering this resync
  # as_of - The Time to stop searching to (inclusive)
  #
  # Example
  #   workflow.resync(
  #     actor: current_user,
  #     to:    Time.current
  #   )
  def resync!(actor:, as_of:)
    cards = cards_needing_resync(as_of: as_of).to_a
    cards.each do |card|
      GitHub.dogstats.increment("job.resync_project_workflows.card_resynced")
      run(
        issue: card.content, # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        actor: actor,
      )
    end
  end

  # Internal: Run each of this workflow's actions on a given Issue
  #
  # issue - The Issue to transition
  # actor - The User triggering the workflow
  #
  # Example
  #   workflow.run(issue: my_issue, actor: current_user)
  def run(issue:, actor:)
    actions.each { |action| action.perform(issue: issue, actor: actor) }
  end

  # Internal: Decides if running a workflow is still necessary
  #
  # If a project is closed, workflows don't run. This method decides if
  # cards for that issue need workflow run in the specified time period.
  #
  # as_of - The Time to stop searching to (inclusive)
  #
  # Example
  #   workflow.should_run(issue: issue, as_of: Time.current)
  #   => true
  #
  # Returns a Boolean
  def should_run?(issue:, as_of:)
    # Job should run if Pull Request approval state changed as part of synchronization.
    # That is code owner required reviews were either added or removed.
    if trigger_type == PR_PENDING_APPROVAL_TRIGGER && issue.pull_request&.base_branch_rule_evaluator&.require_code_owner_review
      policy_decision = issue.pull_request&.merge_state.pull_request_review_policy_decision
      return true unless policy_decision.approved?
    end

    !cards_needing_resync(as_of: as_of).where(content: issue).empty?
  end

  def self.workflow_description(trigger_type, verbose: false)
    case trigger_type
    when ISSUE_CLOSED_TRIGGER
      if verbose
        "If an open issue in this project is closed, it will automatically move here."
      else
        "Closed"
      end
    when ISSUE_PENDING_CARD_ADDED_TRIGGER
      if verbose
        "Issues will automatically move here when added to this project."
      else
        "Newly added"
      end
    when ISSUE_REOPENED_TRIGGER
      if verbose
        "If a closed issue in this project reopens, it will automatically move here."
      else
        "Reopened"
      end
    when PR_APPROVED_TRIGGER
      if verbose
        "Pull requests in this project will automatically move here when they meet the minimum number of required approving reviews."
      else
        "Approved by reviewer"
      end
    when PR_CLOSED_NOT_MERGED_TRIGGER
      if verbose
        "If an open pull request in this project is closed with unmerged commits, it will automatically move here."
      else
        "Closed with unmerged commits"
      end
    when PR_PENDING_APPROVAL_TRIGGER
      if verbose
        "Pull requests in this project will automatically move here when a reviewer requests changes, or it no longer meets the minimum number of required approving reviews."
      else
        "Pending approval by reviewer"
      end
    when PR_PENDING_CARD_ADDED_TRIGGER
      if verbose
        "Pull requests will automatically move here when added to this project."
      else
        "Newly added"
      end
    when PR_MERGED_TRIGGER
      if verbose
        "If an open pull request in this project is merged, it will automatically move here."
      else
        "Merged"
      end
    when PR_REOPENED_TRIGGER
      if verbose
        "If a closed pull request in this project reopens, it will automatically move here."
      else
        "Reopened"
      end
    end
  end

  def event_context(prefix: event_prefix)
    {
      prefix => trigger_type,
      "#{prefix}_id".to_sym => id,
    }
  end

  def event_payload
    {
      project_workflow: self,
      project_column: project_column,
      project: project,
      rank: 4,
    }
  end

  def instrument_creation
    return unless project_column.present?
    instrument :create
  end

  def instrument_update
    return unless previous_changes.has_key?("project_column_id") && project_column.present?

    old_column_id = previous_changes["project_column_id"].first
    return instrument_creation if old_column_id.nil?

    old_column = ProjectColumn.find_by_id(old_column_id)

    changes_payload = {
      old_column_id: old_column_id,
      old_column_name: old_column&.name,
      column_id: project_column.id,
      column_name: project_column.name,
    }

    instrument :update, changes: changes_payload
  end

  def instrument_deletion
    instrument :delete
  end

  def self.duplicate_workflow_with_new_trigger(new_trigger_type, old_workflow, old_creator)
    workflow = old_workflow.dup
    workflow.trigger_type = new_trigger_type
    workflow.created_at = old_workflow.created_at
    workflow.updated_at = old_workflow.updated_at
    workflow.creator = old_creator
    workflow
  end
  private_class_method :duplicate_workflow_with_new_trigger

  def self.feature_enabled?(issue, feature_name)
    return false unless repo = issue.repository
    FeatureFlag.vexi.enabled_or_raise?(feature_name, repo) || (repo.owner.is_a?(Organization) && FeatureFlag.vexi.enabled_or_raise?(feature_name, repo.owner)) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end
  private_class_method :feature_enabled?

  # Public: Used to check if a trigger should be changed or ignored.
  #
  # trigger - The triggering event.
  # issue   - The issue to check the trigger on.
  # payload - The payload that may contain additional details needed.
  #           Ex: for dismissed reviews, the id of the review.
  #
  # Returns a String trigger if the trigger is relevant, else nil.
  def self.filter_trigger(trigger, issue, payload)
    return unless issue.present?
    return if PR_ONLY_TRIGGERS.include?(trigger) && !issue.pull_request?

    filtered_trigger = trigger
    case trigger
    when PR_APPROVED_TRIGGER
      filtered_trigger = nil unless review_approved?(issue)
    when PR_PENDING_APPROVAL_TRIGGER
      filtered_trigger = nil if review_approved?(issue)
    when PR_CLOSED_NOT_MERGED_TRIGGER
      # When a PR is merged, it fires a close and merge event
      # so we need to check the merged status to be sure
      # the PR_CLOSED_NOT_MERGED_TRIGGER should be run.
      if issue.pull_request.merged?
        filtered_trigger = nil
      end
    when REVIEW_DISMISSED_TRIGGER
      filtered_trigger = if review_approved?(issue)
        PR_APPROVED_TRIGGER
      else
        PR_PENDING_APPROVAL_TRIGGER
      end
    end
    filtered_trigger
  end

  # Public: Retrieve the workflows matching the trigger and issue.
  #          Used for events triggered on an issue/PR change.
  #
  # trigger - The triggering event.
  # issue   - The issue that triggered the event.
  # project_card_id - For pending card added events, the card that was added
  # offset_id - Offset of workflows for processing in next batch
  # batch_size - Number of workflows to process
  # tags - Stats tags passed for better tracking
  #
  # Returns an array of ProjectWorkflows that match the trigger and issue if
  # they exist.
  def self.externally_triggered_workflows(trigger, issue, project_card_id: nil, offset_id: nil, batch_size: nil, tags: nil)
    return unless trigger && issue

    project_ids = if PENDING_CARD_TRIGGERS.include?(trigger)
      # scope to the project the card was added to
      card = ProjectCard.find_by_id(project_card_id)
      if card&.project&.open? && card.project.owner.projects_enabled?
        [card.project_id]
      end
    else
      issue.projects.open_projects.owner_projects_enabled.ids
    end

    return unless project_ids.present?

    GitHub.dogstats.count("job.process_project_workflows.projects", project_ids.size, tags: tags)

    if offset_id.nil? || batch_size.nil?
      where(trigger_type: trigger, project_id: project_ids).joins(:actions)
    else
      where(trigger_type: trigger, project_id: project_ids).where("id > ?", offset_id).limit(batch_size).order(:id).includes(:actions)
    end
  end

  # Private: Check if the pull request associated with the given issue has
  #          review approval.
  def self.review_approved?(issue)
    issue.pull_request.approved_with_no_changes_requested?
  end
  private_class_method :review_approved?

  private

  # Private: If actor is found, set them as the last_updater.
  def set_updater
    self.last_updater = User.find_by_id(GitHub.context[:actor_id])
  end

  def track_project_workflow_creation
    GitHub.dogstats.increment("project_workflow.created", tags: ["trigger_type:#{trigger_type}"])
  end

  def track_project_workflow_deletion
    GitHub.dogstats.increment("project_workflow.deleted", tags: ["trigger_type:#{trigger_type}"])
  end
end
