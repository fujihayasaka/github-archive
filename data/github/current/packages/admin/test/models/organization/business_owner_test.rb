# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationBusinessOwnerTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @bus_owner = create(:user)
    @org_owner = create(:user)
    @business = create(:business, owners: [@bus_owner])
    @org       = create(:organization, business: @business, admin: @org_owner)
    @user      = create(:user)
  end

  setup do
    @business_owner = Organization::BusinessOwner.new(
      organization: @org,
      business_owner: @bus_owner)
  end

  context "#business_owner?" do
    test "false if the business owner is set to an org owner" do
      @org_owner = Organization::BusinessOwner.new(
        organization: @org,
        business_owner: @org_owner)
      refute @org_owner.business_owner?
    end

    test "false if the org does not have a business" do
      other_org = create(:organization)
      @org_owner = Organization::BusinessOwner.new(
        organization: other_org,
        business_owner: @org_owner)
      refute @org_owner.business_owner?
    end

    test "false if the org is nil" do
      @org_owner = Organization::BusinessOwner.new(
        business_owner: @org_owner)
      refute @org_owner.business_owner?
    end

    test "false if the business owner is set to an org member" do
      @user_owner = Organization::BusinessOwner.new(
        organization: @org,
        business_owner: @user)
      refute @user_owner.business_owner?
    end

    test "true if the business owner is modifying themselves" do
      assert @business_owner.business_owner?
    end
  end

  context "#change_role" do
    test "succeeds for a business owner becoming an org owner" do
      result = @business_owner.change_role("owner")
      assert result.success?
    end

    test "succeeds for a business owner becoming a member" do
      result = @business_owner.change_role("direct_member")
      assert result.success?
    end

    test "succeeds for a business owner removing themselves" do
      @org.add_member @bus_owner, action: :admin
      result = @business_owner.change_role("unaffiliated")
      assert result.success?
    end

    test "fails for a business owner removing themselves as last org owner" do
      @org.add_member @bus_owner, action: :admin
      perform_enqueued_jobs(only: [RemoveOrgAdminJob, RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        @org.remove_member(@org_owner)
      end

      result = @business_owner.change_role("unaffiliated")
      assert_equal result, Organization::BusinessOwnerStatus::NO_OWNERS
    end

    test "fails for a business owner who is the last owner when changing from owner to member" do
      @org.add_member @bus_owner, action: :admin
      perform_enqueued_jobs(only: [RemoveOrgAdminJob, RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        @org.remove_member(@org_owner)
      end

      result = @business_owner.change_role("direct_member")
      assert_equal result, Organization::BusinessOwnerStatus::NO_OWNERS
    end

    test "no change when a non member trying to remove themselves" do
      result = @business_owner.change_role("unaffiliated")
      assert_equal result, Organization::BusinessOwnerStatus::NO_CHANGE
    end

    test "not successful with blank role" do
      result = @business_owner.change_role("")
      assert_equal result, Organization::BusinessOwnerStatus::NOT_SUCCESSFUL
    end

    test "not successful with a garbage role" do
      result = @business_owner.change_role("garbage")
      assert_equal result, Organization::BusinessOwnerStatus::NOT_SUCCESSFUL
    end

    test "not successful for an org unaffiliated with business" do
      other_org = create(:organization)
      @business_owner = Organization::BusinessOwner.new(
        organization: other_org,
        business_owner: @bus_owner)

      result = @business_owner.change_role("owner")
      assert_equal result, Organization::BusinessOwnerStatus::NOT_SUCCESSFUL
    end

    test "not successful for a suspended business owner" do
      @bus_owner.suspend "Reasons"
      @business_owner = Organization::BusinessOwner.new(
        organization: @org,
        business_owner: @bus_owner)

      result = @business_owner.change_role("owner")
      assert_equal result, Organization::BusinessOwnerStatus::INVALID_USER_STATE
    end

    test "not successful for a business owner that is also an enterprise team synced member" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      @business_owner = Organization::BusinessOwner.new(
        organization: @org,
        business_owner: @bus_owner)
      enterprise_team = create :enterprise_team, business: @business
      team = create :team, organization: @org
      team.add_member(@bus_owner)

      # Force creation of OrgMembershipEntry
      ability = Ability.user_direct_read_on_organization(actor_id: @bus_owner.id, subject_id: @org.id).pluck(:id)
      OrganizationMembershipEntry.create_entry(user: @bus_owner, organization_id: @org.id, ability_id: ability.first, derived: true, adder_id: team.id, adder_type: :enterprise_team)

      result = @business_owner.change_role("unaffiliated")
      assert_equal Organization::BusinessOwnerStatus::MEMBER_IN_SYNCED_ENTERPRISE_TEAM, result
    end unless GitHub.single_business_environment?

    test "instruments owner role removal" do
      @business.add_owner(@org_owner, actor: @bus_owner)
      @business.remove_owner(@bus_owner, actor: @org_owner)
      assert_hydro_published({
        enterprise: Hydro::EntitySerializer.business(@business),
        actor: Hydro::EntitySerializer.user(@org_owner),
        user: Hydro::EntitySerializer.user(@bus_owner),
        role: "owner",
        new_role: ""
      }, schema: "github.enterprise_account.v0.EnterpriseRemoveAdmin")
    end

    test "instruments with new role" do
      @business.add_owner(@org_owner, actor: @bus_owner)
      @business.change_admin_role(@bus_owner, new_role: "billing_manager", actor: @org_owner)
      assert_hydro_published({
        enterprise: Hydro::EntitySerializer.business(@business),
        actor: Hydro::EntitySerializer.user(@org_owner),
        user: Hydro::EntitySerializer.user(@bus_owner),
        role: "owner",
        new_role: "billing_manager"
      }, schema: "github.enterprise_account.v0.EnterpriseRemoveAdmin")
    end unless GitHub.single_business_environment?
  end
end

class OrganizationBusinessOwnerEmuTest < GitHub::TestCase
  test "change_role should return EMU_MEMBER_IN_EXTERNAL_GROUP when business owner is an EMU member in an external group", skip_enterprise: true do
    business = create :business, :enterprise_managed
    owner = business.find_first_emu_owner

    organization_admin = create :emu, business: business
    organization = create :organization, business: business, admin: organization_admin

    external_group = create :external_group, :with_members, business: business, number_of_members: 2

    derived_membership = external_group.members[1]
    organization_derived_user = derived_membership.external_identity.user

    business.add_owner(organization_derived_user, actor: owner)

    bus_owner = Organization::BusinessOwner.new(
      organization: organization,
      business_owner: organization_derived_user
    )

    assert Organization::BusinessOwnerStatus::EMU_MEMBER_IN_EXTERNAL_GROUP, bus_owner.change_role("unaffiliated")
  end
end

class OrganizationBusinessOwnerSAMLTest < GitHub::TestCase
  fixtures do
    @bus_owner = create(:user)
    @org_owner = create(:user)
    @business  = create(:business, owners: [@bus_owner])
    @saml_org = create(:organization, admins: [@org_owner])
    create(:organization_saml_provider, organization: @saml_org)
    @business.add_organization @saml_org

  end

  context "#change_role" do
    test "succeeds for joining a SAML enabled org" do
      business_owner = Organization::BusinessOwner.new(
        organization: @saml_org,
        business_owner: @bus_owner)

      result = business_owner.change_role("owner")
      assert result.success?
    end

    # Saml enforced does not exist for single business environment
    unless GitHub.single_business_environment?
      test "fails when joining a SAML enforced org" do
        @saml_org.saml_provider.enforce!

        business_owner = Organization::BusinessOwner.new(
          organization: @saml_org,
          business_owner: @bus_owner)

        result = business_owner.change_role("owner")
        assert_equal result, Organization::BusinessOwnerStatus::SAML_ENFORCED
      end

      test "succeeds when joining a SAML enforced org transferred to a business with SAML enabled" do
        @saml_org.saml_provider.enforce!
        create(:business_saml_provider, business: @business)

        business_owner = Organization::BusinessOwner.new(
        organization: @saml_org,
        business_owner: @bus_owner)

        result = business_owner.change_role("owner")
        assert result.success?
      end

      test "succeeds for changing roles in a SAML enforced org" do
        @saml_org.add_member @bus_owner
        @saml_org.saml_provider.enforce!

        business_owner = Organization::BusinessOwner.new(
          organization: @saml_org,
          business_owner: @bus_owner)

        result = business_owner.change_role("owner")
        assert result.success?
      end
    end
  end
end
