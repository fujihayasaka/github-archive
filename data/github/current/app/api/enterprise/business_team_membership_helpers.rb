# typed: strict
# frozen_string_literal: true

module Api::Enterprise::BusinessTeamMembershipHelpers
  extend T::Helpers

  requires_ancestor { Api::EnterpriseTeamMemberships }

  sig { void }
  def list_business_team_memberships; end

  sig { void }
  def get_business_team_membership; end

  sig { void }
  def create_business_team_membership; end

  sig { void }
  def bulk_create_business_team_memberships; end

  sig { void }
  def delete_business_team_membership; end

  sig { void }
  def bulk_delete_business_team_memberships; end
end
