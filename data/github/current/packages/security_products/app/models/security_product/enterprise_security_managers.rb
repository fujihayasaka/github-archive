# typed: true
# frozen_string_literal: true

module SecurityProduct
  class EnterpriseSecurityManagers
    sig { params(business: ::Business).void }
    def initialize(business)
      @business = business
    end

    # Returns the users who are security managers for the business.
    sig { returns(T::Array[User]) }
    def users
      # We only need to consider ESMs assigned through business teams, because direct assignment is not supported.
      # If this changes in the future, we'll need to query UserRole for actor_type = User as well and merge the results.

      team_member_ids = Team.member_ids_indexed_by_team_ids(self.team_ids, immediate_only: true, with_business_teams: true).values.flatten.uniq
      return [] if team_member_ids.empty?
      users = User.where(id: team_member_ids).to_a
    end

    private

    # Returns the IDs of the business' security manager teams.
    sig { returns(T::Array[Integer]) }
    def team_ids
      # Custom roles are not supported for the :manage_enterprise_security_products role today, so FGP-based assignment is not considered here.
      role = EnterpriseRole.enterprise_security_manager_role
      UserRole.where(actor_type: BusinessTeam, role: role, target: @business).pluck(:actor_id)
    end
  end
end
