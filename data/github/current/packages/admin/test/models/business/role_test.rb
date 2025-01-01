# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessRoleTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "bus-owner")
    @business = create(:business, owners: [@owner])

    @billing_manager = create(:user)
    @business.billing.add_manager(@billing_manager, actor: @owner)

    org = create(:organization)
    @business.add_organization(org)

    @member = create(:user, login: "org-member")
    org.add_member(@member)

    @outside_collaborator = create(:user, login: "outside-collaborator")
    create(:repository, :minimal, owner: org).add_member(@outside_collaborator)

    @unaffiliated = create(:user, login: "unaffiliated")
  end

  context "::name_for_type and ::description_for_type" do
    test "returns 'Unaffiliated' for nil" do
      name = Business::Role.name_for_type nil
      assert_equal "Unaffiliated", name

      description = Business::Role.description_for_type nil, nil
      assert_equal "This person isn’t affiliated with the enterprise account.", description
    end

    test "returns 'Enterprise account owner' for :owner" do
      name = Business::Role.name_for_type :owner
      assert_equal "Enterprise account owner", name

      description = Business::Role.description_for_type :owner, nil
      assert_equal "Owners have full administrative rights to the enterprise account.", description
    end

    test "returns 'Organization member' for :member" do
      name = Business::Role.name_for_type :member
      assert_equal "Organization member", name

      role = Business::Role.new(@business, @member, organization_count: 1)
      description = Business::Role.description_for_type :member, role
      assert_equal "This person is a member of 1 organization within the enterprise account.", description
      role = Business::Role.new(@business, @member, organization_count: 5)
      description = Business::Role.description_for_type :member, role
      assert_equal "This person is a member of 5 organizations within the enterprise account.", description
    end

    test "returns 'Outside collaborator' for :outside_collaborator" do
      name = Business::Role.name_for_type :outside_collaborator
      assert_equal "Outside collaborator", name

      role = Business::Role.new(@business, @outside_collaborator, collab_repo_count: 1)
      description = Business::Role.description_for_type :outside_collaborator, role
      assert_equal "This person has access to 1 repository in enterprise organizations that they are not a member of.", description
      role = Business::Role.new(@business, @outside_collaborator, collab_repo_count: 5)
      description = Business::Role.description_for_type :outside_collaborator, role
      assert_equal "This person has access to 5 repositories in enterprise organizations that they are not a member of.", description
    end

    test "returns 'Billing manager' for :billing_manager" do
      name = Business::Role.name_for_type :billing_manager
      assert_equal "Billing manager", name

      description = Business::Role.description_for_type :billing_manager, nil
      assert_equal "Billing managers can view and manage billing for the enterprise account.", description
    end

    test "returns 'Enterprise Server member' for :server_member" do
      name = Business::Role.name_for_type :server_member
      assert_equal "Enterprise Server member", name

      role = Business::Role.new(@business, @member, installation_count: 1)
      description = Business::Role.description_for_type :server_member, role
      assert_equal "This person is a member of 1 server installation within the enterprise account.", description
      role = Business::Role.new(@business, @member, installation_count: 8)
      description = Business::Role.description_for_type :server_member, role
      assert_equal "This person is a member of 8 server installations within the enterprise account.", description
    end

    test "returns 'Unaffiliated' for anything else" do
      name = Business::Role.name_for_type :nix
      assert_equal "Unaffiliated", name

      description = Business::Role.description_for_type :nix, nil
      assert_equal "This person isn’t affiliated with the enterprise account.", description
    end
  end

  context "#types" do
    test "returns [:unaffiliated] for unaffiliated members" do
      role = Business::Role.new(@business, nil)

      assert_equal [:unaffiliated], role.types
    end

    test "returns nil for nil business" do
      role = Business::Role.new(nil, @member)

      assert_nil role.types
    end

    test "returns an array of all roles the user has" do
      role = Business::Role.new(@business, @member, organization_count: 1)

      assert_equal [:member], role.types

      @business.billing.add_manager(@member, actor: @owner)
      role = Business::Role.new(@business, @member, organization_count: 1, installation_count: 2)

      assert_same_elements [:billing_manager, :member, :server_member], role.types
    end

    test "returns [:owner] for business admins" do
      role = Business::Role.new(@business, @owner)

      assert_equal [:owner], role.types
    end

    test "returns [:member] for members of 1 or more orgs" do
      role = Business::Role.new(@business, @member, organization_count: 1)

      assert_equal [:member], role.types
    end

    test "returns [:server_member] for members of 1 or more enterprise installations" do
      role = Business::Role.new(@business, @member, installation_count: 1)

      assert_equal [:server_member], role.types
    end

    test "returns [:server_member] for server-only members" do
      role = Business::Role.new(@business, nil, installation_count: 1)

      assert_equal [:server_member], role.types
    end

    test "returns [:outside_collaborator] for outside collaborators" do
      role = Business::Role.new(@business, @outside_collaborator, collab_repo_count: 1)

      assert_equal [:outside_collaborator], role.types
    end

    test "returns [:billing_manager] for a business billing manager" do
      role = Business::Role.new(@business, @billing_manager)

      assert_equal [:billing_manager], role.types
    end

    test "returns an array with :unaffiliated if user has no roles" do
      role = Business::Role.new(@business, @unaffiliated)
      assert_equal [:unaffiliated], role.types
    end
  end
end

unless GitHub.single_business_environment?
  class BusinessRoleForEmusTest < GitHub::TestCase
    fixtures do
      @guest_collaborator = create(:emu, :guest_collaborator)
      @emu_business = @guest_collaborator.enterprise_managed_business
    end

    context "::name_for_type and ::description_for_type" do
      test "returns 'Guest collaborator' for :guest_collaborator" do
        name = Business::Role.name_for_type :guest_collaborator
        assert_equal "Guest collaborator", name

        role = Business::Role.new(@emu_business, @guest_collaborator)
        description = Business::Role.description_for_type :guest_collaborator, role
        assert_equal "Guest collaborators only have access to internal repositories within organizations where they are a member.", description
      end
    end

    context "#types" do
      test "returns [:guest_collaborator] for guest collaborators" do
        role = Business::Role.new(@emu_business, @guest_collaborator)

        assert_equal [:guest_collaborator], role.types
      end
    end
  end
end
