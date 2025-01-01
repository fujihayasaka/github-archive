# typed: true
# frozen_string_literal: true

# A simple object used by ProjectTemplate to create column templates
#
# See ProjectTemplate for usage instructions :sparkles:
#
class ProjectColumnTemplate
  attr_reader :purpose
  attr_accessor :workflows, :cards, :name

  def initialize(name:, purpose: nil, workflows: [])
    @name = name
    @purpose = purpose
    @workflows = workflows
    @cards = []
  end

  def data
    {
      name: @name,
      purpose: @purpose,
    }
  end

  def self.kanban
    [to_do, in_progress, done]
  end

  def self.kanban_with_reviews
    [to_do, in_progress, needs_review, reviewer_approved, done]
  end

  def self.bug_triage
    triage = to_do(include_cards: false)
    triage.name = "Needs triage"
    triage.workflows << ProjectWorkflow::ISSUE_REOPENED_TRIGGER

    closed = done
    closed.name = "Closed"

    high = new(name: "High priority")
    low = new(name: "Low priority")

    [triage, high, low, closed]
  end

  def self.to_do(include_cards: true)
    column = new(name: "To do", purpose: ProjectColumn::PURPOSE_TODO, workflows: [ProjectWorkflow::ISSUE_PENDING_CARD_ADDED_TRIGGER])

    if include_cards
      column.cards.concat(ProjectCardTemplate.all_prioritized)
    end

    column
  end

  def self.in_progress
    workflows = [ProjectWorkflow::PR_PENDING_CARD_ADDED_TRIGGER, ProjectWorkflow::ISSUE_REOPENED_TRIGGER, ProjectWorkflow::PR_REOPENED_TRIGGER]

    new(name: "In progress", purpose: ProjectColumn::PURPOSE_IN_PROGRESS, workflows: workflows)
  end

  def self.needs_review
    new(name: "Review in progress", purpose: ProjectColumn::PURPOSE_IN_PROGRESS, workflows: [ProjectWorkflow::PR_PENDING_APPROVAL_TRIGGER])
  end

  def self.reviewer_approved
    new(name: "Reviewer approved", purpose: ProjectColumn::PURPOSE_IN_PROGRESS, workflows: [ProjectWorkflow::PR_APPROVED_TRIGGER])
  end

  def self.done
    new(name: "Done", purpose: ProjectColumn::PURPOSE_DONE, workflows: ProjectWorkflow::DONE_TRIGGERS.dup)
  end
end
