# typed: strict
# frozen_string_literal: true

class BusinessTeamOrgAssignment < ApplicationRecord::Domain::Users
  self.table_name = "business_team_org_assignments"

  attribute :added_by, :integer
  enum :added_by, { enterprise: 0, org: 1 }, prefix: true

  belongs_to :business_team, foreign_key: :team_id, inverse_of: :business_team_org_assignments
  validates_presence_of :business_team

  belongs_to :organization
  belongs_to :business
  validates_presence_of :organization
  validates_presence_of :business

  validate :business_team_limit_can_create_more_org_assignments, on: :create
  validate :enforce_organization_teams_limit, on: :create

  after_create_commit :instrument_organization_teams_limit_events

  private

  sig { void }
  def business_team_limit_can_create_more_org_assignments
    if business_team&.organization_assignments_limit_reached?
      errors.add(:business_team, "organization assignment limit reached")
    end
  end

  sig { void }
  def enforce_organization_teams_limit
    return unless organization.present?
    return unless T.must(organization).new_enterprise_platform_limits_enforced?

    if T.must(organization).teams_limit_reached?
      self.errors.add(:organization, T.must(organization).teams_limit_reached_message)
    end
  end

  # The creation of a BusinessTeamOrgAssignment effectively adds a BusinessTeam to the "team count" for
  # an Organization, so perform any teams per org instrumentation needed.
  sig { void }
  def instrument_organization_teams_limit_events
    T.must(organization).instrument_teams_limit_events
  end
end
