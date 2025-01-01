# typed: true
# frozen_string_literal: true

class ReviewRequestDelegationExcludedMember < ApplicationRecord::Collab
  belongs_to :team
  validates :team, presence: true

  belongs_to :user
  validates :user, presence: true


  # Public: update the list of team members to never auto-assign to code review
  #
  # team - the team whose settings to update
  # excluded_member_ids - list of user ids representing team members to never auto-assign
  # exclude_team_members - boolean representing whether the "never assign certain team members" box was last checked or unchecked
  def self.update_excluded_team_members(team:, excluded_member_ids:, exclude_team_members: false)
    ReviewRequestDelegationExcludedMember.transaction do
      self.where(team_id: team.id).delete_all

      if exclude_team_members
        new_excluded_member_list = User.find(T.let(excluded_member_ids, T::Array[Integer])).map do |user|
          { user: user, team: team }
        end

        self.create!(new_excluded_member_list)
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => ex
      raise ActiveRecord::Rollback, ex.message
    end
  end

  def self.update_team_members(team, excluded_team_members)
    ReviewRequestDelegationExcludedMember.transaction do
      self.where(team: team).delete_all
      new_excluded_member_list = excluded_team_members.map do |user_id|
        { user_id: user_id, team: team }
      end
      self.create!(new_excluded_member_list)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      raise ActiveRecord::Rollback, e.message
    end
  end
end
