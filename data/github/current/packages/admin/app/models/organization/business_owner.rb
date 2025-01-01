# typed: true
# frozen_string_literal: true

# An Organization::BusinessOwner is a representation of the actions a business
# owner can perform within an organization.
class Organization::BusinessOwner
  attr_reader :organization, :business_owner

  def initialize(organization: nil, business_owner: nil)
    @organization = organization
    @business_owner = business_owner
  end

  # Public: Change the business owner's role within the org.
  #
  # role - Required String representing the new role for the owner within
  #   the given org. Must be one of:
  #   - "owner" to make them an owner
  #   - "direct_member" to make them a member
  #   - "unaffiliated" to remove them from the org
  #
  # Returns a Organization::BusinessOwnerStatus indicating status
  def change_role(role)
    unless business_owner?
      return Organization::BusinessOwnerStatus::NOT_SUCCESSFUL
    end

    if role.blank?
      return Organization::BusinessOwnerStatus::NOT_SUCCESSFUL
    end

    unless @organization.two_factor_requirement_met_by?(@business_owner)
      return Organization::BusinessOwnerStatus::NO_2FA
    end

    unless valid_join_org_state?
      return Organization::BusinessOwnerStatus::INVALID_USER_STATE
    end

    if joining_saml_enforced_org? && !@organization.business&.saml_sso_enabled? # SAML enforcement shouldn't apply for EA-owned orgs
      return Organization::BusinessOwnerStatus::SAML_ENFORCED
    end

    if role == "owner"
      if @organization.direct_or_team_member?(@business_owner)
        @organization.update_member(@business_owner, action: :admin, updater: @business_owner)
      else
        @organization.add_admin(@business_owner, adder: @business_owner)
      end
      return successful_role_change(Organization::BusinessOwnerStatus::SUCCESS_OWNER)
    end

    if role == "direct_member"
      begin
        if @organization.direct_or_team_member?(@business_owner)
          @organization.update_member(@business_owner, action: :read, updater: @business_owner)
        else
          @organization.add_member(@business_owner, adder: @business_owner)
        end
        return successful_role_change(Organization::BusinessOwnerStatus::SUCCESS_MEMBER)
      rescue Organization::NoAdminsError
        return Organization::BusinessOwnerStatus::NO_OWNERS
      end
    end

    if role == "unaffiliated"
      if @organization.direct_or_team_member?(@business_owner)
        begin
          @organization.remove_member(@business_owner, background_team_remove_member: true)
          rescue Organization::NoAdminsError
            return Organization::BusinessOwnerStatus::NO_OWNERS
          rescue Organization::UnableToRemoveEmuError
            return Organization::BusinessOwnerStatus::EMU_MEMBER_IN_EXTERNAL_GROUP
          rescue Organization::UnableToRemoveEnterpriseTeamMemberError
            return Organization::BusinessOwnerStatus::MEMBER_IN_SYNCED_ENTERPRISE_TEAM
        end
        return successful_role_change(Organization::BusinessOwnerStatus::SUCCESS_REMOVED)
      else
        return Organization::BusinessOwnerStatus::NO_CHANGE
      end
    end

    Organization::BusinessOwnerStatus::NOT_SUCCESSFUL
  end

  # Public: Whether the given business owner is an owner for the org's
  # business
  #
  # Returns a boolean.
  def business_owner?
    # Checks if a business owner is changing roles
    @organization&.business&.owner?(@business_owner)
  end

  private

  # Private: Simple proxy to instrument successful role change and return status.
  #
  # status - Organization::BusinessOwnerStatus representing the result
  #
  # Returns Organization::BusinessOwnerStatus
  def successful_role_change(status)
    instrument_change_role(status)
    status
  end

  # Private: Instrument successful role change.
  #
  # status - Organization::BusinessOwnerStatus for instrumentation payload
  #
  # Returns nothing.
  def instrument_change_role(status)
    role_changed_to = case status
    when Organization::BusinessOwnerStatus::SUCCESS_OWNER
      :ADMIN
    when Organization::BusinessOwnerStatus::SUCCESS_MEMBER
      :MEMBER
    when Organization::BusinessOwnerStatus::SUCCESS_REMOVED
      :REMOVED
    else
      :UNKNOWN
    end

    GlobalInstrumenter.instrument("enterprise_account.owner_role_change_in_organization", {
      enterprise: organization.business,
      organization: organization,
      actor: business_owner,
      role_changed_to: role_changed_to
    })
  end

  # Private: Is the user in a valid state to become a member of the
  # organization?
  #
  # Returns Boolean
  def valid_join_org_state?
    !@business_owner.suspended? && !@business_owner.deceased?
  end

  # Private: Is the user trying to join a saml enforced org?
  #
  # Returns Boolean
  def joining_saml_enforced_org?
    return false if @organization.direct_or_team_member?(@business_owner)
    @organization.saml_sso_enforced?
  end
end
