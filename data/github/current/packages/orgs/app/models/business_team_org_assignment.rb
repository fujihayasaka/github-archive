# typed: strict
# frozen_string_literal: true

class BusinessTeamOrgAssignment < ApplicationRecord::Domain::Users
  self.table_name = "business_team_org_assignments"

  belongs_to :business_team, foreign_key: :team_id, inverse_of: :business_team_org_assignments
  validates_presence_of :business_team

  belongs_to :organization
  validates_presence_of :organization

  validate :business_team_limit_can_create_more_org_assignments, on: :create

  sig { returns(T::Boolean) }
  private def organization_assignment_limit_reached?
    return false unless business_team.present?
    T.must(business_team).organization_assignment_limit_reached?
  end

  sig { void }
  private def business_team_limit_can_create_more_org_assignments
    errors.add(:business_team, "organization assignment limit reached") if organization_assignment_limit_reached?
  end
end
