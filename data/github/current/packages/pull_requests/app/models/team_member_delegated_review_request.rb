# typed: true
# frozen_string_literal: true

class TeamMemberDelegatedReviewRequest < ApplicationRecord::Collab
  validates_presence_of :team_id, :member_id, :pull_request_id, :delegated_at

  def self.upsert(team_id:, member_id:, delegated_at:)
    self.connection.insert(Arel.sql(<<~SQL, team_id: team_id, member_id: member_id, delegated_at: delegated_at))
        INSERT INTO `team_member_delegated_review_requests`
          (`team_id`, `member_id`, `delegated_at`)
        VALUES (:team_id, :member_id, :delegated_at)
        ON DUPLICATE KEY UPDATE
          `id` = LAST_INSERT_ID(`id`), `delegated_at` = :delegated_at
      SQL
  end
end
