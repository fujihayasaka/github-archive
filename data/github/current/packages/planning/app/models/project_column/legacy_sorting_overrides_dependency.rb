# typed: false
# frozen_string_literal: true

# Overrides for Prioritizable::Context until all projects have been backfilled.
# The intention here is to perform writes of new position values, etc. but use
# the legacy ProjectColumn#ordered_card_ids field as the source of truth for
# reads.
#
# TODO: After the backfill of existing data is complete and data quality is
# verified on the new prioritization implementation, this file should be
# removed.

module ProjectColumn::LegacySortingOverridesDependency
  class PrioritizingArchivedCardError < StandardError; end
  class InvalidPrioritizationTargetError < StandardError; end
  class InvalidSqlStatementError < StandardError; end

  CARD_COLLISION_RETRY_LIMIT = 8

  def prioritize_card!(card, after: nil, position: nil, new_card: false, automated: false, actor_id: nil, workflow_action_id: nil)
    raise PrioritizingArchivedCardError.new("Cannot prioritize archived cards") if card.archived?
    raise InvalidPrioritizationTargetError.new("After target is not prioritized") if after && after.priority.nil?

    return card if card.new_record? && !card.valid?

    # grab some values before transaction completes to use for the move event
    previous_column = card.column

    # verify that the target column does not contain too many cards
    # noop if it is full :grimacing:
    moving_columns = self != previous_column
    exceeds_max = cards.not_archived.size >= ProjectColumn::MAX_CARDS
    if moving_columns && exceeds_max
      GitHub.dogstats.increment("project_column.prioritization.column_max_exceeded")
      return card
    end

    card.show_activity = new_card || self != previous_column

    collision_retries = 0

    GitHub.dogstats.distribution_time("project_column.dist.prioritize_card_loop") do
      loop do
        begin
          card = prioritize_dependent!(card, after: after, position: position)
          card.save if card&.changed?
          GitHub.dogstats.increment("project_column.prioritization.success")
        rescue ActiveRecord::StatementInvalid => e
          card.priority = nil
          collision_retries += 1
          GitHub.dogstats.increment("project_column.prioritization.collision_retry", tags: ["retry_count:#{collision_retries}"])

          # If it's this card's first collision, also log with the legacy key,
          # and report to Failbot in case it's some other type of error.
          if collision_retries == 1
            GitHub.dogstats.increment("project_column.prioritization.collision")
            Failbot.report(
              InvalidSqlStatementError.new("card_id: #{card.id}"),
              {
                app: "github-projects",
                "gh.actor.id": actor_id,
                "gh.projects.workflow_action.id": workflow_action_id
              }.compact
            )
          end
        end

        break if card.priority.present? || collision_retries >= CARD_COLLISION_RETRY_LIMIT
      end
    end

    if card.new_record?
      card.update(priority: nil, column: self)
    end

    self.save!

    track_prioritization_errors(card, actor_id, workflow_action_id)

    if card.content.is_a?(Issue) && previous_column != self
      if previous_column.nil?
        card.content.trigger_add_to_project_event( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          column: self,
          project: project,
          card_id: card.id,
        )
      else
        card.content.trigger_move_within_project_event( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          column: self,
          previous_column_name: previous_column.name,
          project: project,
          card: card,
        )
      end
    end

    card.trigger_moved_event(after_card: after, previous_column: previous_column, automated: automated) unless new_card

    card
  end

  private

  # Returns all cards in the passed list of ids, preserving order.
  def cards_by_id(ids)
    return [] if ids.empty?
    cards.where(id: ids).order(Arel.sql("FIELD(id, #{ids.join(",")})")).order("id")
  end

  def track_prioritization_errors(card, actor_id, workflow_action_id)
    if card.priority.nil?
      Failbot.push(
        {
          "gh.projects.card.id": card.id,
          "gh.actor.id": actor_id,
          "gh.projects.workflow_action.id": workflow_action_id
        }.compact
      )
      Failbot.report(StandardError.new("ProjectCard prioritized with nil priority"), app: "github-projects")
    end
  end
end
