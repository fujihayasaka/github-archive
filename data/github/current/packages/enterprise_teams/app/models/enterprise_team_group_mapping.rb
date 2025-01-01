# typed: strict
# frozen_string_literal: true
class EnterpriseTeamGroupMapping < ApplicationRecord::Domain::Users
  extend T::Sig
  include Instrumentation::Model

  belongs_to :enterprise_team
  belongs_to :external_group

  validates :enterprise_team_id, uniqueness: { scope: :external_group_id }
  validates_presence_of :enterprise_team, :external_group

  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }
  scope :owned_by, -> (enterprise_team) { where(enterprise_team_id: Array(enterprise_team).map(&:id)) }

  after_commit :instrument_team_update, on: [:create, :update]
  after_commit :instrument_idp_group_mapping_create, on: [:create]
  after_commit :instrument_idp_group_mapping_update, on: [:update]

  sig { void }
  def soft_delete
    update!(deleted_at: Time.now)
  end

  sig { void }
  def instrument_team_update
    enterprise_team = self.enterprise_team

    return if enterprise_team.nil?

    enterprise_team.instrument_update
  end

  sig { void }
  def instrument_idp_group_mapping_create
    enterprise_team = self.enterprise_team

    return if enterprise_team.nil?

    enterprise_team.instrument_idp_group_mapping(:provision)
  end

  sig { void }
  def instrument_idp_group_mapping_update
    enterprise_team = self.enterprise_team

    return if enterprise_team.nil?

    # If a soft delete or undo delete happened
    if previous_changes.include?("deleted_at")

      # If it's a soft delete, only emit remove events
      if previous_changes["deleted_at"].first.nil? && previous_changes["deleted_at"].last.present?
        old_group = external_group
      end

      # If it's a undo delete, only emit add events
      if previous_changes["deleted_at"].first.present? && previous_changes["deleted_at"].last.nil?
        new_group = external_group
      end

    # If it's a group switch, combination of remove and adds
    elsif previous_changes.include?("external_group_id")
      old_group = ExternalGroup.find(previous_changes["external_group_id"].first)
      new_group = external_group
    end

    # Get old group / new group members based on whether we need to emit events for those
    removed_members_candidate = old_group&.active_user_ids || []
    added_members_candidate = new_group&.active_user_ids || []

    # Members can be part of both old and new groups, cancel those each other out
    removed_members = removed_members_candidate - added_members_candidate
    added_members = added_members_candidate - removed_members_candidate

    # Emit events
    removed_members.each do |user_id|
      enterprise_team.instrument_remove_member(User.find(user_id))
    end
    added_members.each do |user_id|
      enterprise_team.instrument_add_member(User.find(user_id))
    end
  end
end
