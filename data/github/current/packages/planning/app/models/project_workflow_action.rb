# typed: false
# frozen_string_literal: true

class ProjectWorkflowAction < ApplicationRecord::Domain::Projects
  include GitHub::Relay::GlobalIdentification

  TRANSITION_TO_COLUMN = "transition_to_column".freeze

  ACTIONS = [TRANSITION_TO_COLUMN].freeze

  belongs_to :creator, class_name: "User"
  belongs_to :last_updater, class_name: "User"
  belongs_to :project_workflow
  belongs_to :project, inverse_of: :project_workflow_actions

  delegate :project_column, to: :project_workflow

  validates :creator, presence: true
  validates :action_type, inclusion: { in: ACTIONS }
  validates :project_workflow, presence: true

  def self.locate(type)
    return unless ACTIONS.include?(type.to_s)
    where(action_type: type).first
  end

  # Public: Performs the saved action.
  #
  # issue - Issue that triggered the workflow.
  # actor - Actor that triggered the workflow.
  def perform(issue:, actor:)
    GitHub.dogstats.distribution_time("project_workflow_action.dist") do
      context_values = {
        actor_id: actor.id,
        project_workflow_action_id: id,
        project_workflow_action: action_type,
        project_workflow_trigger: project_workflow.trigger_type,
      }

      GitHub.context.push(context_values) do
        Audit.context.push(context_values) do
          # Currently, there is only one action_type
          if action_type == TRANSITION_TO_COLUMN
            GitHub.dogstats.distribution_time("project_workflow_action.dist.transition_to_column") do
              transition_to_column(issue: issue, actor: actor)
              project.notify_subscribers(action: "card_update", message: "#{actor} updated a card via automation")
            end
          end
        end
      end
    end
  end

  private

  # Private: Runs the column transition action.
  #
  # issue - the issue to search for among the project's cards
  # actor - the actor that triggered the workflow
  #
  # Returns a Boolean
  def transition_to_column(issue:, actor:)
    if project_column
      cards = issue.cards.not_archived.where(project_id: project_id)

      return unless cards.present?

      if cards.size > 1
        # there should only be one card
        GitHub.dogstats.increment("project_workflow_actions.transition_to_column.multiple_cards")
      end

      # TODO: On each prioritization, rescue
      # GitHub::Prioritizable::Context::LockedForRebalance, sleep, and try again.
      cards.each do |card|
        project_column.prioritize_card!(
          card,
          position: default_column_position,
          automated: true,
          actor_id: actor.id,
          workflow_action_id: id
        )
      end
    end
  end

  # Private: Determines whether to insert the card at the bottom or top of column.
  #
  # Returns :top or :bottom
  def default_column_position
    return unless project_column
    if project_column.automated_with_done_triggers?
      :top
    else
      :bottom
    end
  end
end
