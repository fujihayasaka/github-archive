# typed: true
# frozen_string_literal: true

require "test_helper"

module OrganizationRoleSharedTests
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { OrganizationRoleBaseTest }

  included do
    T.bind(self, T.class_of(OrganizationRoleBaseTest))

    test "type_returns_nil_for_nil_members" do
      role = Organization::Role.new(@org, nil)

      assert_nil role.type
    end

    test "type_returns_nil_for_nil_organizations" do
      role = Organization::Role.new(nil, @member)

      assert_nil role.type
    end

    test "type_returns_admin_for_org_admins" do
      role = Organization::Role.new(@org, @owner)

      assert_equal :admin, role.type
    end

    test "type_returns_direct_member_for_org_members" do
      role = Organization::Role.new(@org, @member)

      assert_equal :direct_member, role.type
    end

    test "types_returns_nil_for_nil_members" do
      role = Organization::Role.new(@org, nil)

      assert_nil role.types
    end

    test "types_returns_nil_for_nil_organizations" do
      role = Organization::Role.new(nil, @member)

      assert_nil role.types
    end

    test "types_returns_an_array_of_all_roles_the_user_has" do
      role = Organization::Role.new(@org, @member)

      assert_equal [:direct_member], role.types

      @org.billing.add_manager(@member, actor: @owner)
      role = Organization::Role.new(@org, @member)

      assert_same_elements [:billing_manager, :direct_member], role.types
    end

    test "types_returns_admin_for_org_admins" do
      role = Organization::Role.new(@org, @owner)

      assert_equal [:admin], role.types
    end

    test "types_returns_direct_member_for_org_members" do
      role = Organization::Role.new(@org, @member)

      assert_equal [:direct_member], role.types
    end

    test "types_returns_billing_manager_for_a_billing_manager" do
      @org.billing.add_manager(@billing_manager, actor: @owner)
      role = Organization::Role.new(@org, @billing_manager)

      assert_equal [:billing_manager], role.types
    end

    test "can_be_modified_is_true_for_owners_viewing_another_member" do
      role = Organization::Role.new(@org, @member)

      assert role.can_be_modified_by?(@owner)
    end

    test "can_be_modified_is_false_for_owners_viewing_themselves" do
      role = Organization::Role.new(@org, @owner)

      refute role.can_be_modified_by?(@owner)
    end

    test "can_be_modified_is_false_for_non_owners_viewing_themselves" do
      role = Organization::Role.new(@org, @member)

      refute role.can_be_modified_by?(@member)
    end

    test "can_be_modified_is_false_for_non_owners_viewing_another_member" do
      role = Organization::Role.new(@org, @other)

      refute role.can_be_modified_by?(@member)
    end
  end
end

class OrganizationRoleBaseTest < GitHub::TestCase
end

class OrganizationRoleTest < OrganizationRoleBaseTest
  include OrganizationRoleSharedTests

  fixtures do
    @owner = create(:user, login: "org-owner")
    @org = create(:organization, admin: @owner)

    @billing_manager = create(:user)

    @member = create(:user, login: "org-member")
    @org.add_member(@member)

    @other = create(:user)
    @org.add_member @other

    enterprise = create(:global_business)
    provider = create :business_saml_provider, business: enterprise

    @suspended = create(:user, login: "org-suspended")
    @org.add_member(@suspended)
    identity = create :external_identity, provider: provider, user: @suspended
    identity.disable

    @outside_collaborator = create(:user, login: "outside-collaborator")
    create(:repository, :minimal, owner: @org).add_member(@outside_collaborator)

    @unaffiliated = create(:user, login: "unaffiliated")
  end

  context "::name_for_type" do
    test "returns Unaffiliated for nil" do
      name = Organization::Role.name_for_type nil
      assert_equal "Unaffiliated", name
    end

    test "returns Owner for :admin" do
      name = Organization::Role.name_for_type :admin
      assert_equal "Owner", name
    end

    test "returns Member for :direct_member" do
      name = Organization::Role.name_for_type :direct_member
      assert_equal "Member", name
    end

    test "returns Member for :member" do
      name = Organization::Role.name_for_type :member
      assert_equal "Member", name
    end

    test "returns Suspended member for :suspended" do
      name = Organization::Role.name_for_type :suspended
      assert_equal "Suspended member", name
    end

    test "returns Outside collaborator for :outside_collaborator" do
      name = Organization::Role.name_for_type :outside_collaborator
      assert_equal "Outside collaborator", name
    end

    test "returns Billing manager for :billing_manager" do
      name = Organization::Role.name_for_type :billing_manager
      assert_equal "Billing manager", name
    end

    test "returns Reinstate for :reinstate" do
      name = Organization::Role.name_for_type :reinstate
      assert_equal "Reinstate", name
    end

    test "returns Unaffiliated for anything else" do
      name = Organization::Role.name_for_type :nix
      assert_equal "Unaffiliated", name
    end
  end

  context "type" do
    test "returns :direct_member for suspended org members" do
      role = Organization::Role.new(@org, @suspended)

      assert_equal :direct_member, role.type
    end

    test "returns :outside_collaborator for outside collaborators" do
      role = Organization::Role.new(@org, @outside_collaborator)

      assert_equal :outside_collaborator, role.type
    end

    test "returns :unaffiliated for unaffiliated users" do
      role = Organization::Role.new(@org, @unaffiliated)

      assert_equal :unaffiliated, role.type
    end
  end

  context "#types" do
    test "returns [:direct_member] for suspended org members" do
      role = Organization::Role.new(@org, @suspended)

      assert_equal [:direct_member], role.types
    end


    test "returns an array with :unaffiliated if user has no roles" do
      role = Organization::Role.new(@org, @unaffiliated)
      assert_equal [:unaffiliated], role.types
    end
  end

  context "can_be_modified_by?" do
    test "is true for owners viewing an suspended members" do
      role = Organization::Role.new(@org, @suspended)

      assert role.can_be_modified_by?(@owner)
    end

    test "is false for owners viewing an outside collaborator" do
      role = Organization::Role.new(@org, @outside_collaborator)

      refute role.can_be_modified_by?(@owner)
    end

    test "is false for owners viewing an unaffiliated member" do
      role = Organization::Role.new(@org, @unaffiliated)

      refute role.can_be_modified_by?(@owner)
    end
  end

  context "outside_collaborator?" do
    test "is true for non-members that have permissions on org-owned repos" do
      role = Organization::Role.new(@org, @outside_collaborator)

      assert_predicate role, :outside_collaborator?
    end

    test "is false for non-members that have no permissions on org-owned repos" do
      outsider = create(:user)

      role = Organization::Role.new(@org, @unaffiliated)

      refute_predicate role, :outside_collaborator?
    end
  end
end

class EmuOrganizationRoleTest < OrganizationRoleBaseTest
  skip_enterprise

  include OrganizationRoleSharedTests

  fixtures do
    @owner = create(:emu, :owner, login: "org-owner")
    business = @owner.enterprise_managed_business

    @billing_manager = create(:emu, business: business)
    @org = create(:organization, business: business, admin: @owner)

    @member = create(:emu, business: business, login: "org-member")
    @org.add_member(@member)

    @other = create(:emu, business: business)
    @org.add_member @other

    @suspended = create(:emu, business: business, login: "org-suspended")
    @org.add_member(@suspended)
    @suspended.external_identities.first.disable

    @suspended2 = create(:emu, business: business, login: "org-suspended-no-identity")
    @org.add_member(@suspended2)
    @suspended2.external_identities.first.destroy

    @first_emu_owner = @suspended2.enterprise_managed_business.find_first_emu_owner
  end

  context "type" do
    test "returns :suspended for suspended org members" do
      role = Organization::Role.new(@org, @suspended)

      assert_equal :suspended, role.type
    end
  end

  context "#types" do
    test "returns [:suspended, :direct_member] for suspended org members" do
      role = Organization::Role.new(@org, @suspended)

      assert_equal [:suspended, :direct_member], role.types
    end
  end

  context "can_be_modified_by?" do
    test "is false for owners viewing an suspended members" do
      role = Organization::Role.new(@org, @suspended)

      refute role.can_be_modified_by?(@owner)
    end
  end

  context "#suspended?" do
    test "not suspended organization member returns false" do
      role = Organization::Role.new(@org, @member)

      refute_predicate role, :suspended?
    end

    test "suspended organization member returns true" do
      role = Organization::Role.new(@org, @suspended)

      assert_predicate role, :suspended?
    end

    test "organization member without external identity returns true" do
      role = Organization::Role.new(@org, @suspended2)

      assert_predicate role, :suspended?
    end

    test "returns false for initial EMU enterprise owner", skip_enterprise: true do
      assert_predicate @first_emu_owner, :is_first_emu_owner?

      role = Organization::Role.new(@org, @first_emu_owner)

      refute_predicate role, :suspended?
    end
  end
end
