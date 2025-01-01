# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationBillingManagementDependencyTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @user = create(:user)
  end

  context "#billing" do
    test "returns a Organization::BillingManagement instance" do
      @org.billing.is_a?(Organization::BillingManagement)
    end
  end

  context "#billing_manager?" do
    test "false if the user is not a billing manager of the org" do
      refute @org.billing_manager?(@user)
      refute @org.async_billing_manager?(@user).sync
    end

    test "true if the user is a billing manager of the org" do
      @org.billing.add_manager(@user, actor: @org.admins.first)
      assert_able @user, :write, @org.billing
      assert @org.billing_manager?(@user)
      assert @org.async_billing_manager?(@user).sync
    end
  end

  context "#billing_managers" do
    test "returns all billing managers for the organization" do
      @org.billing.add_manager(@user, actor: @org.admins.first)
      assert_same_elements [@user], @org.billing_managers
    end

    test "returns an empty array if there are no billing managers in the org" do
      assert_empty @org.billing_managers
    end
  end

  context "#billing_users" do
    test "returns an array of self for an organization with no billing managers" do
      org = create(:organization)
      assert_empty org.billing_managers
      assert_equal [org], org.billing_users
    end

    test "includes billing managers if any exist for the organization" do
      org = create(:organization)
      billing_manager = create(:user)
      org.billing.add_manager(billing_manager, actor: org.admins.first)
      assert_same_elements [org, billing_manager], org.billing_users
    end
  end
end

class UserWithBillingManagementAccessToAnOrganizationTest < GitHub::TestCase
  fixtures do
    @org  = create(:organization)
    @repo = create(:private_repository, owner: @org)
    @billing_manager = create(:user)
    @org.billing.add_manager(@billing_manager, actor: @org.admins.first)
  end

  test "can't view a repo" do
    refute @repo.pullable_by?(@billing_manager)
  end

  test "can't push to a repo" do
    refute @repo.pushable_by?(@billing_manager)
  end

  test "can't admin a repo" do
    refute @repo.adminable_by?(@billing_manager)
  end

  test "is not a member of the org" do
    refute @org.direct_or_team_member?(@billing_manager)
  end
end
