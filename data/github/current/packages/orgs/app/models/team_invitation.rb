# typed: true
# frozen_string_literal: true

class TeamInvitation < ApplicationRecord::Domain::Users
  belongs_to :organization_invitation
  belongs_to :inviter, class_name: "User"
  belongs_to :team

  validates_presence_of :organization_invitation, :inviter, :team
  validates_uniqueness_of :team_id, scope: :organization_invitation_id
  validates :role, presence: true

  enum :role, { member: 0, maintainer: 1 }

  def self.valid_role?(role)
    TeamInvitation.roles[role].present?
  end
end
