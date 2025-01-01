# typed: strict
# frozen_string_literal: true

module Organization::BusinessTeamsDependency
  extend T::Helpers
  requires_ancestor { Organization }

  # Thrown when someone attempts to remove an user with BT membership that prevents the user from being removed from the org
  class UnableToRemoveBusinessTeamMemberError < StandardError; end

  sig { params(user: User).returns(T::Boolean) }
  def business_team_prevents_removal_from_org?(user)
    return false unless business.present?
    return false unless T.must(business).erp_feature_enabled?(:enterprise_teams_org_assignment)
    Orgs.domain.teams.business_team_ids_with_assigned_orgs_for(user_id: user.id, organization_id: id).any?
  end

  sig { params(users: T::Array[User]).returns(T::Array[User]) }
  def prevent_removal_of_business_team_members_from_org(users)
    return users unless business.present?
    return users unless T.must(business).erp_feature_enabled?(:enterprise_teams_org_assignment)

    user_ids = users.map(&:id)
    user_ids -= Orgs.domain.teams.business_team_user_ids(user_ids: user_ids, organization_id: id)

    users.select { |user| user_ids.include?(user.id) }
  end
end
