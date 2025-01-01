# typed: true
# frozen_string_literal: true

class ReviewRequestDelegationIncludedMember < ApplicationRecord::Collab
  belongs_to :team
  validates :team, presence: true

  belongs_to :user
  validates :user, presence: true

  def self.update_team_members(team, included_team_members)
    ReviewRequestDelegationIncludedMember.transaction do
      self.where(team: team).delete_all
      new_included_member_list = included_team_members.map do |user_id|
        { user_id: user_id, team: team }
      end
      self.create!(new_included_member_list)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      raise ActiveRecord::Rollback, e.message
    end
  end
end
