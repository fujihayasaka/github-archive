# typed: true
# frozen_string_literal: true

require "test_helper"

unless GitHub.single_business_environment?
  class BusinessUserAccountRolesTest < GitHub::TestCase
    fixtures do
      @admin = create :user, login: "business-admin"
      @org1 = create :organization, admin: @admin
      @org2 = create :organization, admin: @admin
      @business = create :business, owners: [@admin], organizations: [@org1, @org2]
      @member = create :user
    end

    setup do
      perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
        @org1.add_member @member
      end
      @business_user_account = @business.business_user_account_for(@member)
    end

    test "business roles values only contain powers of 2" do
      BusinessUserAccount::Roles::BUSINESS_ROLES.each_value do |value|
        next if value == 0
        assert_equal Math.log2(value) % 1, 0
      end
    end

    test "business roles values are all unique" do
      values = BusinessUserAccount::Roles::BUSINESS_ROLES.values
      assert_equal values.uniq.length, values.length
    end

    context "business_roles" do
      test "returns an empty array when roles have not been defined yet" do
        assert_equal [], @business_user_account.business_roles
      end

      test "returns unaffiliated for users with no roles in the business" do
        @business_user_account.set_business_roles([])

        assert_equal [:unaffiliated], @business_user_account.business_roles
      end

      test "returns an array with appropriate role for business user account" do
        @business_user_account.business_roles_bitfield = BusinessUserAccount::Roles::BUSINESS_ROLES[:member]

        assert_equal [:member], @business_user_account.business_roles
      end

      test "returns an array with multiple roles when multiple roles are set" do
        @business_user_account.business_roles_bitfield = (BusinessUserAccount::Roles::BUSINESS_ROLES[:member] | BusinessUserAccount::Roles::BUSINESS_ROLES[:owner])

        assert_equal [:member, :owner], @business_user_account.business_roles
      end
    end

    context "add_business_roles" do
      test "adds role to the business_role field" do
        @business_user_account.add_business_roles([:member])

        assert_equal [:member], @business_user_account.business_roles
      end

      test "adds multiple roles to the business_role field" do
        @business_user_account.add_business_roles([:member, :owner])

        assert_equal [:member, :owner], @business_user_account.business_roles
      end

      test "can add existing roles without duplication" do
        @business_user_account.business_roles_bitfield = BusinessUserAccount::Roles::BUSINESS_ROLES[:member]
        @business_user_account.add_business_roles([:member, :owner])

        assert_equal [:member, :owner], @business_user_account.business_roles
      end

      test "skips over invalid roles" do
        @business_user_account.business_roles_bitfield = BusinessUserAccount::Roles::BUSINESS_ROLES[:member]
        @business_user_account.add_business_roles([:invalid_role, :owner])

        assert_equal [:member, :owner], @business_user_account.business_roles
      end
    end

    context "remove_business_roles" do
      test "removes multiple roles from the business_role field" do
        @business_user_account.business_roles_bitfield = BusinessUserAccount::Roles::BUSINESS_ROLES[:member] | BusinessUserAccount::Roles::BUSINESS_ROLES[:owner]
        @business_user_account.remove_business_roles([:member])

        assert_equal [:owner], @business_user_account.business_roles
      end

      test "can handle removing non assigned roles" do
        @business_user_account.business_roles_bitfield = BusinessUserAccount::Roles::BUSINESS_ROLES[:member] | BusinessUserAccount::Roles::BUSINESS_ROLES[:billing_manager]
        @business_user_account.remove_business_roles([:member, :owner])

        assert_equal [:billing_manager], @business_user_account.business_roles
      end

      test "can handle removing invalid roles" do
        @business_user_account.business_roles_bitfield = BusinessUserAccount::Roles::BUSINESS_ROLES[:member] | BusinessUserAccount::Roles::BUSINESS_ROLES[:billing_manager]
        @business_user_account.remove_business_roles([:invalid_role, :member])

        assert_equal [:billing_manager], @business_user_account.business_roles
      end
    end

    context "set_business_roles" do
      test "sets role on user accounts" do
        @business_user_account.set_business_roles([:billing_manager, :owner])

        assert_same_elements [:billing_manager, :owner], @business_user_account.business_roles
      end

      test "removes existing business roles that are not passed in" do
        @business_user_account.business_roles_bitfield = (BusinessUserAccount::Roles::BUSINESS_ROLES[:member] | BusinessUserAccount::Roles::BUSINESS_ROLES[:owner])
        @business_user_account.set_business_roles([:billing_manager, :outside_collaborator])

        assert_same_elements [:outside_collaborator, :billing_manager], @business_user_account.business_roles
      end

      test "can handle adding existing roles" do
        @business_user_account.business_roles_bitfield = (BusinessUserAccount::Roles::BUSINESS_ROLES[:member] | BusinessUserAccount::Roles::BUSINESS_ROLES[:owner])
        @business_user_account.set_business_roles([:billing_manager, :member])

        assert_same_elements [:member, :billing_manager], @business_user_account.business_roles
      end

      test "will set user to unaffiliated if passed an empty array" do
        @business_user_account.business_roles_bitfield = (BusinessUserAccount::Roles::BUSINESS_ROLES[:member] | BusinessUserAccount::Roles::BUSINESS_ROLES[:owner])
        @business_user_account.set_business_roles([])

        assert_same_elements [:unaffiliated], @business_user_account.business_roles
      end

      test "will set to unaffiliated when passed unaffiliated" do
        @business_user_account.business_roles_bitfield = (BusinessUserAccount::Roles::BUSINESS_ROLES[:member] | BusinessUserAccount::Roles::BUSINESS_ROLES[:owner])
        @business_user_account.set_business_roles([:unaffiliated])

        assert_same_elements [:unaffiliated], @business_user_account.business_roles
      end

      test "will skip invalid roles" do
        @business_user_account.set_business_roles([:member, :invalid_role, :owner])

        assert_same_elements [:member, :owner], @business_user_account.business_roles
      end
    end

    context "has_no_business_role?" do
      test "returns true when user has undefined roles" do
        assert_equal [], @business_user_account.business_roles
        assert @business_user_account.has_no_business_role?
      end

      test "returns true if business roles is unaffiliated" do
        @business_user_account.business_roles_bitfield = BusinessUserAccount::Roles::BUSINESS_ROLES[:unaffiliated]
        assert @business_user_account.has_no_business_role?
      end

      test "returns false when user has business roles" do
        @business_user_account.business_roles_bitfield = BusinessUserAccount::Roles::BUSINESS_ROLES[:billing_manager]
        refute @business_user_account.has_no_business_role?
      end
    end
  end
end
