# typed: true
# frozen_string_literal: true

require "test_helper"

class Business2faAuthenticationDependencyTest < GitHub::TestCase
  fixtures do
    @admin = create(:user)
    @org1 = create(:organization, admins: [@admin])
    @org2 = create(:organization, admins: [@admin])
    @repo = create(:repository, owner: @org1)
    @business = create(:business, owners: [@admin], organizations: [@org1, @org2])
  end

  context "#owners_with_two_factor_disabled" do
    test "it finds business admins with 2fa disabled" do
      user = create :user
      @business.add_owner(user, actor: @admin)

      refute user.two_factor_authentication_enabled?
      assert_includes @business.owners_with_two_factor_disabled, user
    end

    test "it does not find business admins with 2fa enabled" do
      user = create(:user)
      make_two_factor_credential(user)
      @business.add_owner(user, actor: @admin)

      assert user.two_factor_authentication_enabled?
      refute_includes @business.owners_with_two_factor_disabled, user
    end
  end

  context "#members_with_two_factor_disabled" do
    test "it finds users with 2fa disabled" do
      user = create(:user)
      @org1.add_member(user)

      refute user.two_factor_authentication_enabled?
      assert_includes @business.members_with_two_factor_disabled, user
    end

    test "it doesn't find users with 2fa enabled" do
      user = create(:user)
      make_two_factor_credential(user)
      @org1.add_member(user)

      assert user.two_factor_authentication_enabled?
      assert_includes @business.organization_members, user
      refute_includes @business.members_with_two_factor_disabled, user
    end
  end

  context "#outside_collaborators_with_two_factor_disabled" do
    test "it finds outside collaborators with 2fa disabled" do
      collaborator = create(:user)
      RepositoryInvitation.invite_to_repo_without_confirmation(collaborator, @admin, @repo)

      refute collaborator.two_factor_authentication_enabled?
      assert_includes @business.outside_collaborators_with_two_factor_disabled, collaborator
    end

    test "it doesn't find outside collaborators with 2fa enabled" do
      collaborator = create(:user)
      make_two_factor_credential(collaborator)
      RepositoryInvitation.invite_to_repo_without_confirmation(collaborator, @admin, @repo)

      assert collaborator.two_factor_authentication_enabled?
      assert_includes @business.outside_collaborators, collaborator
      refute_includes @business.outside_collaborators_with_two_factor_disabled, collaborator
    end
  end

  context "#billing_managers_with_two_factor_disabled" do
    test "it finds billing managers with 2fa disabled" do
      billing_manager = create(:user)
      Business::BillingManagement.new(@business).add_manager(billing_manager, actor: @admin)

      refute billing_manager.two_factor_authentication_enabled?
      assert_includes @business.billing_managers_with_two_factor_disabled, billing_manager
    end

    test "it does not find billing managers with 2fa enabled" do
      billing_manager = create(:user)
      make_two_factor_credential(billing_manager)
      Business::BillingManagement.new(@business).add_manager(billing_manager, actor: @admin)

      assert billing_manager.two_factor_authentication_enabled?
      assert_includes @business.billing_managers, billing_manager
      refute_includes @business.billing_managers_with_two_factor_disabled, billing_manager
    end
  end

  context "#affiliated_users_with_two_factor_disabled" do
    test "finds all affiliated users in the business with 2fa disabled" do
      member = create(:user)
      @org1.add_member(member)
      org_billing_manager = create(:user)
      @org1.billing.add_manager(org_billing_manager, actor: @admin)
      collaborator = create(:user)
      RepositoryInvitation.invite_to_repo_without_confirmation(collaborator, @admin, @repo)
      billing_manager = create(:user)
      Business::BillingManagement.new(@business).add_manager(billing_manager, actor: @admin)

      business_affiliated_members = [@admin, member, org_billing_manager, collaborator, billing_manager]

      assert_same_elements business_affiliated_members, @business.affiliated_users_with_two_factor_disabled
    end

    test "users are de-duped across orgs/repos" do
      member = create(:user)
      @org1.add_member(member)
      @org2.add_member(member) # the dupe
      collaborator = create(:user)
      RepositoryInvitation.invite_to_repo_without_confirmation(collaborator, @admin, @repo)
      billing_manager = create(:user)
      Business::BillingManagement.new(@business).add_manager(billing_manager, actor: @admin)

      business_affiliated_members = [@admin, member, collaborator, billing_manager]
      assert_same_elements business_affiliated_members, @business.affiliated_users_with_two_factor_disabled
    end
  end

  context "#affiliated_users_with_two_factor_enabled" do
    test "finds all affiliated users in the business with 2fa enabled" do
      member = create(:user, :two_factor_enabled)
      @org1.add_member(member)
      org_billing_manager = create(:user, :two_factor_enabled)
      @org1.billing.add_manager(org_billing_manager, actor: @admin)
      collaborator = create(:user, :two_factor_enabled)
      RepositoryInvitation.invite_to_repo_without_confirmation(collaborator, @admin, @repo)
      billing_manager = create(:user, :two_factor_enabled)
      Business::BillingManagement.new(@business).add_manager(billing_manager, actor: @admin)

      business_affiliated_members = [member, org_billing_manager, collaborator, billing_manager]

      assert_same_elements business_affiliated_members, @business.affiliated_users_with_two_factor_enabled
    end

    test "users are de-duped across orgs/repos" do
      member = create(:user, :two_factor_enabled)
      @org1.add_member(member)
      @org2.add_member(member) # the dupe
      collaborator = create(:user, :two_factor_enabled)
      RepositoryInvitation.invite_to_repo_without_confirmation(collaborator, @admin, @repo)
      billing_manager = create(:user, :two_factor_enabled)
      Business::BillingManagement.new(@business).add_manager(billing_manager, actor: @admin)

      business_affiliated_members = [member, collaborator, billing_manager]
      assert_same_elements business_affiliated_members, @business.affiliated_users_with_two_factor_enabled
    end
  end

  context "#affiliated_users_with_two_factor_disabled_exist?" do
    test "returns true if members exist with 2fa disabled" do
      make_two_factor_credential(@admin)
      user = create(:user)
      @org1.add_member(user)

      assert @business.affiliated_users_with_two_factor_disabled_exist?
      # @admin has had 2fa enabled here. sanity check
      assert_equal [user], @business.affiliated_users_with_two_factor_disabled
    end

    test "returns true if collaborators exist with 2fa disabled" do
      collaborator = create(:user)
      RepositoryInvitation.invite_to_repo_without_confirmation(collaborator, @admin, @repo)

      assert @business.affiliated_users_with_two_factor_disabled_exist?
    end

    test "returns true if billing managers exist with 2fa disabled" do
      billing_manager = create(:user)
      Business::BillingManagement.new(@business).add_manager(billing_manager, actor: @admin)

      assert @business.affiliated_users_with_two_factor_disabled_exist?
    end

    test "returns false if no members, collaborators, or billing managers exist with 2fa disabled" do
      make_two_factor_credential(@admin)

      refute @business.affiliated_users_with_two_factor_disabled_exist?
    end
  end

  context "#can_two_factor_requirement_be_enabled?" do
    test "is true when any admins have 2fa enabled" do
      make_two_factor_credential(@admin)
      assert @business.can_two_factor_requirement_be_enabled?
    end

    test "is false when no admins have 2fa enabled" do
      refute @business.can_two_factor_requirement_be_enabled?
    end
  end

  context "#updating_two_factor_requirement?" do
    test "returns true when a business is updating 2fa" do
      # enable getting the desired job status values from the cache
      GitHub.cache.allow = /enforce-two-factor-requirement/

      # enable 2fa on the admin so it can set the requirement below
      make_two_factor_credential(@admin)

      # intentionally not using perform_now so that the job is still
      # in progress
      EnforceTwoFactorRequirementOnBusinessJob.perform_later(@business, @admin)
      assert @business.updating_two_factor_requirement?
    end

    test "returns false when the business is not updating 2fa" do
      # enable getting the desired job status values from the cache
      GitHub.cache.allow = /enforce-two-factor-requirement/

      # enable 2fa on the admin so it can set the requirement below
      make_two_factor_credential(@admin)

      perform_enqueued_jobs(only: [EnforceTwoFactorRequirementOnBusinessJob]) do
        EnforceTwoFactorRequirementOnBusinessJob.perform_later(@business, @admin)
      end
      refute @business.updating_two_factor_requirement?
    end
  end
end

class CanEnableTwoFactorRequirementTest < GitHub::TestCase
  fixtures do
    @two_factor_admin1 = create(:two_factor_credential_user)
    @two_factor_admin2 = create(:two_factor_credential_user)
    @two_factor_org1 = create(:organization, admin: @two_factor_admin1)
    @two_factor_org1.add_admin(@two_factor_admin2)
    @two_factor_org2 = create(:organization, admin: @two_factor_admin1)
    @two_factor_org2.add_admin(@two_factor_admin2)
    @two_factor_business = create(:business, owners: [@two_factor_admin1, @two_factor_admin2], organizations: [@two_factor_org1, @two_factor_org2])
  end

  test "returns all organizations if all admins have 2fa and check for enabled" do
    assert_same_elements [@two_factor_org1, @two_factor_org2], @two_factor_business.organizations_can_enable_two_factor_requirement(true)
  end

  test "returns no organizations if all admins have 2fa and check for disabled" do
    assert_empty @two_factor_business.organizations_can_enable_two_factor_requirement(false)
  end

  test "returns some organizations if some have 2fa admins and check for enabled" do
    @no_two_factor_org = create(:organization)
    @two_factor_business.add_organization(@no_two_factor_org)
    assert_same_elements [@two_factor_org1, @two_factor_org2], @two_factor_business.organizations_can_enable_two_factor_requirement(true)
  end

  test "returns some organizations if some have 2fa admins and check for disabled" do
    @no_two_factor_org = create(:organization)
    @two_factor_business.add_organization(@no_two_factor_org)
    assert_same_elements [@no_two_factor_org], @two_factor_business.organizations_can_enable_two_factor_requirement(false)
  end
end
