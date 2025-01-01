# typed: strict
# frozen_string_literal: true

module Organization::BusinessTeamsDependency
  extend T::Helpers
  requires_ancestor { Organization }

  # Raised when attempting to remove a user from the org, when their membership in a business team
  # prevents removal from the org.
  class UnableToRemoveBusinessTeamMemberError < StandardError; end

  sig { params(user: User).returns(T::Boolean) }
  def business_team_prevents_removal_from_org?(user)
    return false unless business.present?
    return false unless T.must(business).erp_feature_enabled?(:enterprise_teams_org_assignment)
    # If the user is a direct member, permit removal, even if they also have a BusinessTeam membership that
    # gives them indirect Organization membership. Indirect membership is persisted until the user is removed
    # from the relevant BusinessTeams.
    return false if direct_member?(user, include_indirect_abilities: false)
    Orgs.domain.teams.business_team_ids_with_assigned_orgs_for(user_id: user.id, organization_id: id).any?
  end

  sig { params(user: User).returns(T::Boolean) }
  def user_has_both_direct_and_indirect_membership?(user)
    return false unless business.present?
    return false unless T.must(business).erp_feature_enabled?(:enterprise_teams_org_assignment)

    return false unless direct_member?(user, include_indirect_abilities: false)

    Orgs.domain.teams.business_team_ids_with_assigned_orgs_for(user_id: user.id, organization_id: id).any?
  end
end
