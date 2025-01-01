# typed: strict
# frozen_string_literal: true

module EnterpriseTeams
  class Helper
    class UserNotInEnterpriseError < StandardError; end

    sig do
      params(
        enterprise: T.untyped,
        enterprise_team: T.untyped,
        set_security_manager: T::Boolean
      ).void
    end
    def self.configure_security_manager_sync(enterprise:, enterprise_team:, set_security_manager:)
      return unless EnterpriseTeam.enabled_for_organization_security_manager?(enterprise)

      eta = EnterpriseTeamAssignment.where(
        enterprise_team: enterprise_team,
        assignment_type: "security_manager"
      ).first_or_initialize

      if enterprise_team.sync_to_organizations == "all" && set_security_manager
        eta.save!
        SecurityProduct::EnterpriseSecurityManagerRole.grant!(enterprise_team)
      elsif enterprise_team.sync_to_organizations == "disabled" || !set_security_manager
        eta.destroy! unless eta.new_record?
        SecurityProduct::EnterpriseSecurityManagerRole.revoke!(enterprise_team)
      end
    end

    sig { params(enterprise: T.untyped, idp_group_id: T.untyped).returns(NilClass) }
    def self.validate_idp_group_enterprise(enterprise, idp_group_id)
      return unless idp_group_id.present?

      idp_group_id = idp_group_id.to_i

      # Check formatting
      raise ArgumentError, "Invalid external group selection." if idp_group_id <= 0

      # Validate that each ExternalGroup exists and maps to a provider that belongs to the business
      group = ExternalGroup.not_deleted.find_by(id: idp_group_id)
      if group.nil? ||
        (group.provider_type == "Business::SamlProvider" && group.provider_id != enterprise.saml_provider.id) ||
        (group.provider_type == "Business::OIDCProvider" && group.provider_id != enterprise.oidc_provider.id)

        raise ArgumentError, "Invalid external group selection."
      end

      # Raise error if it is GHES. We'll allow eventually, but we have not tested on GHES.
      # Putting this earlier would save minor queries, but it shouldn't be used often enough to matter and
      # makes testing more difficult.
      raise ArgumentError, "External groups for enterprise teams are not supported on GHES." if EnterpriseTeams::Helper.idp_group_disabled?
    end

    sig do
      params(
        current_user: User,
        enterprise_team: EnterpriseTeam,
        query: T.nilable(String)
      ).returns(T.untyped)
    end
    def self.filtered_members(current_user, enterprise_team, query: nil)
      business = T.must(enterprise_team.business)
      business
        .filtered_members(
          current_user,
          query:,
          business_user_accounts_query: business.supports_unaffiliated_user_accounts?,
          include_unaffiliated: true,
          ignore_org_membership_visibility: EnterpriseTeam.enabled_for_organization_security_manager?(business),
          allow_filters_for_non_admin_viewer: true, # lets us use the `deployment: "cloud"` filter for enterprise members
          deployment: "cloud",
        )
      .where(GitHub.enterprise? ? { id: enterprise_team.member_user_ids } : { user_id: enterprise_team.member_user_ids })
    end

    sig { params(enterprise_team: EnterpriseTeam, user: User).void }
    def self.create_team_membership(enterprise_team, user)
      membership = EnterpriseTeamMembership.new(enterprise_team: enterprise_team, user: user)
      membership.save!
    end

    sig { params(business: Business, user_login: T.nilable(String)).returns(User) }
    def self.validate_user_parameter(business, user_login)
      raise ArgumentError, "User login cannot be empty." unless user_login.present?

      user = User.find_by_login(user_login)
      unless user_in_enterprise?(business, user)
        raise UserNotInEnterpriseError, "User cannot be found in the enterprise."
      end

      user
    end

    sig { params(business: Business, user: T.nilable(User)).returns(T::Boolean) }
    def self.user_in_enterprise?(business, user)
      return false if user.nil?
      return true if business.member?(user) || business.owner?(user) || business.unaffiliated_member?(user)

      # Single business environments should allow all single business members. This includes GHES unaffiliated users.
      GitHub.single_business_environment? && business.single_business_members.where(id: user.id).exists?
    end

    sig { params(business: Business, user_logins: T.nilable(T::Array[String])).returns(ActiveRecord::Relation) }
    def self.bulk_validate_user_parameters(business, user_logins)
      raise ArgumentError, "User logins cannot be empty." unless user_logins.present?

      deduplicated_user_logins = user_logins.uniq

      raise ArgumentError, "User logins cannot be empty." if deduplicated_user_logins.empty?

      users = User.with_logins(deduplicated_user_logins)

      raise UserNotInEnterpriseError, "One or more users not found." if users.count != deduplicated_user_logins.count
      raise UserNotInEnterpriseError, "One or more users cannot be found in the enterprise." unless bulk_users_in_enterprise?(business, users)

      users
    end

    sig { params(business: Business, users: ActiveRecord::Relation).returns(T::Boolean) }
    def self.bulk_users_in_enterprise?(business, users)
      user_ids = users.map(&:id)
      buas = BusinessUserAccount.where(business_id: business.id, user_id: user_ids)
      bua_user_ids_set = buas.map(&:user_id).to_set
      # check if each of the users has a BUA
      buas.count == users.count && user_ids.all? { |id| bua_user_ids_set.include?(id) }
    end

    sig { returns(T::Boolean) }
    def self.idp_group_disabled?
      GitHub.enterprise?
    end
  end
end
