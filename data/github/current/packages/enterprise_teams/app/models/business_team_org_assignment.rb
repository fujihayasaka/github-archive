# typed: strict
# frozen_string_literal: true

class BusinessTeamOrgAssignment < ApplicationRecord::Domain::Users
  self.table_name = "business_team_org_assignments"

  belongs_to :business_team, foreign_key: :team_id, inverse_of: :business_team_org_assignments
  belongs_to :organization
end
