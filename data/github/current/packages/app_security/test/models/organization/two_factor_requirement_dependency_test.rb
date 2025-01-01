# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationTwoFactorRequirementEnabledTest < GitHub::TestCase
  test "returns false when organization does not have two factor requirement enabled" do
    refute_predicate create(:organization), :two_factor_requirement_enabled?
  end

  test "returns true when organization has two factor requirement enabled" do
    assert_predicate create(:two_factor_credential_org),
      :two_factor_requirement_enabled?
  end
end

class OrganizationDisableTwoFactorRequirementTest < GitHub::TestCase
  include AuditLogHelpers

  fixtures do
    @owner = create(:user)
    @org = create(:organization, admin: @owner)
    @user = create(:user)
  end

  test "disables 2FA" do
    @org.enable_two_factor_requirement(actor: @owner)

    assert_predicate @org, :two_factor_requirement_enabled?
    @org.disable_two_factor_requirement(actor: @owner)
    refute_predicate @org.reload, :two_factor_requirement_enabled?
  end

  test "disables SMS for 2FA restriction" do
    # enable 2FA required and SMS for 2FA restriction
    @org.enable_two_factor_requirement(actor: @owner)
    @org.enable_restriction_sms_for_2fa(actor: @owner)
    assert_predicate @org, :two_factor_requirement_enabled?
    assert_predicate @org, :sms_for_2fa_restriction_enabled?

    # disable 2FA requirement
    @org.disable_two_factor_requirement(actor: @owner)
    refute_predicate @org.reload, :two_factor_requirement_enabled?

    # SMS restriction is now disabled
    refute_predicate @org, :sms_for_2fa_restriction_enabled?
  end

  test "disabling SMS restriction on org for which it was never configured doesn't impact disabling 2FA requirement" do
    # enable 2FA required
    @org.enable_two_factor_requirement(actor: @owner)
    assert_predicate @org, :two_factor_requirement_enabled?
    refute_predicate @org, :sms_for_2fa_restriction_enabled?

    # disable 2FA requirement
    @org.disable_two_factor_requirement(actor: @owner)

    # SMS restriction still doesn't exist
    refute_predicate @org, :sms_for_2fa_restriction_enabled?
    # 2FA requirement is successfully disabled
    refute_predicate @org.reload, :two_factor_requirement_enabled?
  end

  test "without parameters it does not log an event" do
    events = subscribe "org.disable_two_factor_requirement"

    @org.disable_two_factor_requirement(actor: @owner)

    assert_empty events, "expected there to not be an org.disable_two_factor_requirement event"
  end

  test "with (log_event: true, actor: user) parameters it logs org.disable_two_factor_requirement event" do
    @org.enable_two_factor_requirement(actor: @owner)
    events = subscribe "org.disable_two_factor_requirement"

    expected_payload = {
      actor: @user.login,
      actor_id: @user.id,
      org: @org.login,
      org_id: @org.id,
    }

    @org.disable_two_factor_requirement(log_event: true, actor: @user)

    assert event = events.pop, "expected an org.disable_two_factor_requirement event"
    assert_equal expected_payload, event.payload
  end

  test "removes the Configuration::Entry effectively disabling two_factor_required" do
    @org.enable_two_factor_requirement(actor: @owner)
    assert_predicate @org, :two_factor_requirement_enabled?

    assert_difference("Configuration::Entry.count", -1) do
      @org.disable_two_factor_requirement(actor: @owner)
    end

    refute_predicate @org, :two_factor_requirement_enabled?
  end

  test "does not set a policy for two_factor_required" do
    @org.disable_two_factor_requirement(actor: @owner)
    refute_predicate @org.reload, :two_factor_required_policy?
  end
end

class OrganizationEnableTwoFactorRequirementTest < GitHub::TestCase
  include AuditLogHelpers

  fixtures do
    @org = create(:organization)
    @user = create(:user)
  end

  test "enables 2FA" do
    refute_predicate @org.reload, :two_factor_requirement_enabled?
    @org.enable_two_factor_requirement(actor: @user)
    assert_predicate @org, :two_factor_requirement_enabled?
  end

  test "without parameters it does not log an event" do
    events = subscribe "org.enable_two_factor_requirement"

    @org.enable_two_factor_requirement(actor: @user)

    assert_empty events, "expected there to not be an org.enable_two_factor_requirement event"
  end

  test "with (log_event: true, actor: user) parameters it logs org.enable_two_factor_requirement event" do
    events = subscribe "org.enable_two_factor_requirement"

    expected_payload = {
      actor: @user.login,
      actor_id: @user.id,
      org: @org.login,
      org_id: @org.id,
    }

    @org.enable_two_factor_requirement(log_event: true, actor: @user)

    assert event = events.pop, "expected an org.enable_two_factor_requirement event"
    assert_equal expected_payload, event.payload
  end

  test "adds a Configuration::Entry enabling the two_factor_required Configurable" do
    refute_predicate @org, :two_factor_requirement_enabled?

    assert_difference("Configuration::Entry.count") do
      @org.enable_two_factor_requirement(actor: @user)
    end

    assert_predicate @org, :two_factor_requirement_enabled?
  end

  test "does not set a policy for two_factor_required" do
    @org.enable_two_factor_requirement(actor: @user)
    refute_predicate @org.reload, :two_factor_required_policy?
  end
end

class OrganizationMembersWithTwoFactorDisabledTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @user = create(:user)
    @org.add_member(@user)
  end

  test "returns number of members with 2fa disabled" do
    refute_predicate @user, :two_factor_authentication_enabled?
    refute_predicate @org.admins.first, :two_factor_authentication_enabled?
    assert_equal 2, @org.members_with_two_factor_disabled_count
  end

  test "returns member with 2fa disabled" do
    refute_predicate @user, :two_factor_authentication_enabled?
    assert_includes @org.members_with_two_factor_disabled, @user
  end

  test "returns limited number of members with 2fa disabled" do
    user = create(:user)
    @org.add_member(user)
    refute_predicate @user, :two_factor_authentication_enabled?
    refute_predicate user, :two_factor_authentication_enabled?
    assert @org.members_with_two_factor_disabled.count > 1
    assert_equal 1, @org.members_with_two_factor_disabled(limit: 1).count
  end

  test "does not return member with 2fa enabled" do
    make_two_factor_credential(@user)
    assert_predicate @user, :two_factor_authentication_enabled?
    refute_includes @org.members_with_two_factor_disabled, @user
  end

  test "exist returns false if there is no member with 2fa enabled" do
    make_two_factor_credential(@org.admins.first)
    refute_predicate @user, :two_factor_authentication_enabled?
    assert @org.members_with_two_factor_disabled_exist?
  end

  test "exist returns true if there is any member with 2fa enabled" do
    make_two_factor_credential(@org.admins.first)
    make_two_factor_credential(@user)
    assert_predicate @user, :two_factor_authentication_enabled?
    refute @org.members_with_two_factor_disabled_exist?
  end
end

class OrganizationOutsideCollaboratorsWithTwoFactorDisabledTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @user = create(:user)
    @repo = create(:repository, owner: @org)
    @repo.add_member(@user)
  end

  test "returns number of outside collaborators with 2fa disabled" do
    refute_predicate @user, :two_factor_authentication_enabled?
    assert_equal 1, @org.outside_collaborators_with_two_factor_disabled_count
  end

  test "returns outside collaborator with 2fa disabled" do
    refute_predicate @user, :two_factor_authentication_enabled?
    assert_includes @org.outside_collaborators_with_two_factor_disabled, @user
  end

  test "returns limited number of outside collaborator with 2fa disabled" do
    user = create(:user)
    @repo.add_member(user)
    refute_predicate @user, :two_factor_authentication_enabled?
    refute_predicate user, :two_factor_authentication_enabled?
    assert @org.outside_collaborators_with_two_factor_disabled.count > 1
    assert_equal 1, @org.outside_collaborators_with_two_factor_disabled(limit: 1).count
  end

  test "does not return outside collaborator with 2fa enabled" do
    make_two_factor_credential(@user)
    assert_predicate @user, :two_factor_authentication_enabled?
    refute_includes @org.outside_collaborators_with_two_factor_disabled, @user
  end

  test "exist returns false if there is no outside collaborator with 2fa enabled" do
    refute_predicate @user, :two_factor_authentication_enabled?
    assert @org.outside_collaborators_with_two_factor_disabled_exist?
  end

  test "exist returns true if there is any outside collaborator with 2fa enabled" do
    make_two_factor_credential(@user)
    assert_predicate @user, :two_factor_authentication_enabled?
    refute @org.outside_collaborators_with_two_factor_disabled_exist?
  end
end

class OrganizationBillingManagersWithTwoFactorDisabledTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @user = create(:user)
    @org.billing.add_manager(@user, actor: @org.admins.first)
  end

  test "returns number of billing managers with 2fa disabled" do
    refute_predicate @user, :two_factor_authentication_enabled?
    assert_equal 1, @org.billing_managers_with_two_factor_disabled_count
  end

  test "returns billing managers with 2fa disabled" do
    refute_predicate @user, :two_factor_authentication_enabled?
    assert_includes @org.billing_managers_with_two_factor_disabled, @user
  end

  test "returns limited number of billing managers with 2fa disabled" do
    user = create(:user)
    @org.billing.add_manager(user, actor: @org.admins.first)
    refute_predicate @user, :two_factor_authentication_enabled?
    refute_predicate user, :two_factor_authentication_enabled?
    assert @org.billing_managers_with_two_factor_disabled.count > 1
    assert_equal 1, @org.billing_managers_with_two_factor_disabled(limit: 1).count
  end

  test "does not return billing manager with 2fa enabled" do
    make_two_factor_credential(@user)
    assert_predicate @user, :two_factor_authentication_enabled?
    refute_includes @org.billing_managers_with_two_factor_disabled, @user
  end

  test "exist returns false if there is no billing manager with 2fa enabled" do
    refute_predicate @user, :two_factor_authentication_enabled?
    assert @org.billing_managers_with_two_factor_disabled_exist?
  end

  test "exist returns true if there is any billing manager with 2fa enabled" do
    make_two_factor_credential(@user)
    assert_predicate @user, :two_factor_authentication_enabled?
    refute @org.billing_managers_with_two_factor_disabled_exist?
  end
end

class TwoFactorRequirementMetByTest < GitHub::TestCase
  fixtures do
    @non_org_member = create(:user)
  end

  test "if the inviting org doesn't require 2FA, returns true" do
    non_tfa_org = create(:organization)
    invitation = non_tfa_org.invite(@non_org_member, inviter: non_tfa_org.admin)

    can_join = non_tfa_org.two_factor_requirement_met_by?(@non_org_member)

    assert_equal true, can_join
  end

  test "if invitee meets the org's 2FA requirement, returns true" do
    tfa_invitee = create(:two_factor_credential_user)
    tfa_org = create(:two_factor_credential_org)
    invitation = tfa_org.invite(tfa_invitee, inviter: tfa_org.admin)

    can_join = tfa_org.two_factor_requirement_met_by?(tfa_invitee)

    assert_equal true, can_join
  end

  test "if the invitee doesn't meet the org's 2FA req, returns false" do
    GitHub.flipper[:members_without_2fa_allowed].disable
    non_tfa_invitee = create(:user)
    tfa_org = create(:two_factor_credential_org)
    invitation = tfa_org.invite(non_tfa_invitee, inviter: tfa_org.admin)

    can_join = tfa_org.two_factor_requirement_met_by?(non_tfa_invitee)

    assert_equal false, can_join
  end

  test "even with member_without_2fa_allowed, user without cannot join an org w/ 2FA req, returns false" do
    GitHub.flipper[:members_without_2fa_allowed].enable
    non_tfa_invitee = create(:user)
    tfa_org = create(:two_factor_credential_org)
    invitation = tfa_org.invite(non_tfa_invitee, inviter: tfa_org.admin)

    can_join = tfa_org.two_factor_requirement_met_by?(non_tfa_invitee)

    assert_equal false, can_join
  end
end

class OrganizationTwoFactorRequirementDisabledTest < GitHub::TestCase
  test "returns true if two_factor_requirement_enabled? is false" do
    org = create(:organization)

    assert_predicate org, :two_factor_requirement_disabled?
  end

  test "returns false if two_factor_requirement_enabled? is true" do
    org = create(:two_factor_credential_org)

    refute_predicate org, :two_factor_requirement_disabled?
  end
end

class OrganizationAffiliatedUsersWithTwoFactorDisabledExistTest < GitHub::TestCase
  fixtures do
    @org = create(:two_factor_credential_org)
  end

  test "returns true if org has member with 2fa disabled" do
    user = create(:user)
    make_two_factor_credential(user).tap do |credential, _new_cred|
      @org.add_member(user)
      credential.destroy
    end

    assert_predicate @org, :affiliated_users_with_two_factor_disabled_exist?
  end

  test "returns true if org has outside collaborator with 2fa disabled" do
    user = create(:user)
    repo = create(:private_repository, owner: @org)
    make_two_factor_credential(user).tap do |credential, _new_cred|
      repo.add_member(user)
      credential.destroy
    end

    assert_predicate @org, :affiliated_users_with_two_factor_disabled_exist?
  end

  test "returns false if no enforcement is needed" do
    refute_predicate @org, :affiliated_users_with_two_factor_disabled_exist?
  end
end

class OrganizationEnforcingTwoFactorRequirementTest < GitHub::TestCase
  fixtures do
    @org = create(:two_factor_credential_org)
    @business = create :business, organizations: [@org]
    @status_id = EnforceTwoFactorRequirementOnOrganizationJob.job_id(@org)
    @business_status_id = EnforceTwoFactorRequirementOnBusinessJob.job_id(@business)
  end

  setup do
    GitHub.cache.allow = /enforce-two-factor-requirement/
  end

  test "returns false if no status is found" do
    refute_predicate @org, :enforcing_two_factor_requirement?
  end

  test "returns true if status is found and is not finished" do
    status = JobStatus.create(id: @status_id)
    assert_predicate @org, :enforcing_two_factor_requirement?
    status.destroy
  end

  test "returns false if status is found and is finished" do
    status = JobStatus.create(id: @status_id)
    status.success!
    refute_predicate @org, :enforcing_two_factor_requirement?
    status.destroy
  end

  context "when organization is a member of a business" do
    test "returns true if org status is not found, business job status is found and not finished" do
      status = JobStatus.create(id: @business_status_id)
      assert @org.enforcing_two_factor_requirement?
      status.destroy
    end

    test "returns true if org status is finished, business job status is found and not finished" do
      org_status = JobStatus.create(id: @status_id)
      org_status.success!

      status = JobStatus.create(id: @business_status_id)
      assert @org.enforcing_two_factor_requirement?
      status.destroy
      org_status.destroy
    end

    test "returns false if org status is finished, when business job status is not found" do
      org_status = JobStatus.create(id: @status_id)
      org_status.success!

      refute @org.enforcing_two_factor_requirement?
      org_status.destroy
    end

    test "returns false if org status is not finished, when business job status is not found" do
      org_status = JobStatus.create(id: @status_id)

      assert @org.enforcing_two_factor_requirement?
      org_status.destroy
    end

    test "returns false if business job status is found and is finished" do
      status = JobStatus.create(id: @business_status_id)
      status.success!
      refute @org.enforcing_two_factor_requirement?
      status.destroy
    end
  end

  context "#two_factor_enabled_on_business?" do
    test "returns false if the organization does not belong to a business" do
      org = create(:organization)

      assert_nil org.business
      refute org.two_factor_enabled_on_business?
    end

    test "returns false if the organization's business does not have 2FA enabled" do
      business_owned_org = create :enterprise_linked_organization
      business = business_owned_org.business

      assert business_owned_org.business.present?
      refute business_owned_org.two_factor_enabled_on_business?
    end

    test "returns true if the organization's business has 2FA enabled" do
      business_owned_org = create :enterprise_linked_organization
      business = business_owned_org.business
      business.enable_two_factor_required(actor: business.admins.first)

      assert business_owned_org.business.present?
      assert business_owned_org.two_factor_enabled_on_business?
    end
  end
end

class OrganizationAffiliatedUsersWithTwoFactorDisabledCountTest < GitHub::TestCase
  test "returns the number of unique affiliated users who have 2FA disabled" do
    owner = create(:user, login: "1-admin")
    member_and_billing_manager = create(:user, login: "2-member-and-billing-manager")
    outside_collaborator = create(:user, login: "4-outside-collaborator")
    member_with_2fa = create(:two_factor_credential_user, login: "with-2fa")
    org = create(:organization, admin: owner)
    org.add_member(member_and_billing_manager)
    org.add_member(member_with_2fa)
    org.billing.add_manager(member_and_billing_manager, actor: owner)
    repo = create(:repository, owner: org)
    repo.add_member(outside_collaborator)

    assert_equal 3, org.affiliated_users_with_two_factor_disabled_count
  end

  test "limits the total number of users with 2fa disabled to Organization::TWO_FA_USER_COUNT_LIMIT" do
    owner = create(:user, login: "1-admin")
    member_and_billing_manager = create(:user, login: "2-member-and-billing-manager")
    outside_collaborator = create(:user, login: "4-outside-collaborator")
    member_with_2fa = create(:two_factor_credential_user, login: "with-2fa")
    org = create(:organization, admin: owner)
    org.add_member(member_and_billing_manager)
    org.add_member(member_with_2fa)
    org.billing.add_manager(member_and_billing_manager, actor: owner)
    repo = create(:repository, owner: org)
    repo.add_member(outside_collaborator)

    Organization::TwoFactorRequirementDependency.stub_const(:TWO_FA_USER_COUNT_LIMIT, 2) do
      assert_equal 2, org.affiliated_users_with_two_factor_disabled_count
    end
  end
end

class AffiliatedUsersWithTwoFactorDisabledTest < GitHub::TestCase
  fixtures do
    @admin = create(:user)
    @org1 = create(:organization, admins: [@admin])
  end

  test "finds all affiliated users in the organization with 2fa disabled" do
    member = create(:user)
    @org1.add_member(member)
    repo = create(:repository, owner: @org1)
    collaborator = create(:user)
    repo.add_member_without_validation_or_notifications(collaborator, @admin)
    affiliated_members = [@admin, member, collaborator]

    assert_same_elements affiliated_members, @org1.affiliated_users_with_two_factor_disabled
  end

  test "affiliated users are de-duped across repos" do
    member = create(:user)
    @org1.add_member(member)
    repo1 = create(:repository, owner: @org1)
    repo2 = create(:repository, owner: @org1)
    collaborator = create(:user)
    repo1.add_member_without_validation_or_notifications(collaborator, @admin)
    repo2.add_member_without_validation_or_notifications(collaborator, @admin) # dupe

    affiliated_members = [@admin, member, collaborator]
    assert_same_elements affiliated_members, @org1.affiliated_users_with_two_factor_disabled
  end
end
