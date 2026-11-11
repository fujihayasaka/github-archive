# typed: false
# frozen_string_literal: true

# Scenarios where pull requests are included:
# 1. A pull request has a pending review request from one of the teams
# 2. A pull request has a pending review request from a member of one of the teams
class ReminderTeamFilter
  attr_reader :reminder
  def initialize(reminder)
    @reminder = reminder
  end

  def run(pull_requests)
    return pull_requests unless filtered_by_team?

    pending_reviews = ReviewRequest.where(pull_request_id: pull_requests.map(&:id)).pending.not_dismissed # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    pending_review_from_members = pending_reviews.where(reviewer_id: member_ids).type_users.pluck(Arel.sql("DISTINCT pull_request_id"))
    pending_review_from_teams = pending_reviews.where(reviewer_id: team_ids).type_teams.pluck(Arel.sql("DISTINCT pull_request_id"))
    pull_request_ids_pending_review_from_team_or_members = (pending_review_from_members + pending_review_from_teams).uniq

    pull_requests.select do |pull_request|
      pull_request_ids_pending_review_from_team_or_members.include?(pull_request.id)
    end
  end

  def filtered_by_team?
    team_ids.present?
  end

  def member_ids
    @member_ids ||= teams.flat_map(&:member_ids)
  end

  private

  def teams
    @teams ||= reminder.teams
  end

  def team_ids
    @team_ids ||= teams.map(&:id)
  end
end
