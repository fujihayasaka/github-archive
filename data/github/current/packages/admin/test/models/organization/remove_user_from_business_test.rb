# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationRemoveUserFromBusinessTest < GitHub::TestCase
  fixtures do
    @admin = create :user
    @org = create :organization, plan: GitHub::Plan.business_plus, seats: 10
    @member = create(:user)
    @org.add_member(@member)

    @business = create :business, organizations: [@org], owners: [@admin]
  end

  if GitHub.single_business_environment?
    test "does not remove business user account for single business environment" do
      assert_equal 0, @business.user_accounts.count

      @org.remove_member!(@member)
      assert_equal 0, @business.user_accounts.count
    end
  else
    test "removes member from the business if they are not members of any other org in the business" do
      GitHub.flipper[:unaffiliated_user_accounts].disable
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].disable
      refute_nil @business.business_user_account_for(@member)

      only = [
        RevokeOrgMembershipAbilitiesJob,
        BusinessUserAccountUpdateAttributesJob,
      ]
      perform_enqueued_jobs only: only do
        @org.remove_member!(@member)
      end
      assert_nil @business.business_user_account_for(@member)
    end

    test "does not remove member from the business if the business supports unaffiliated users" do
      GitHub.flipper[:unaffiliated_user_accounts].enable
      assert_equal 3, @business.user_accounts.count

      @org.remove_member!(@member)
      assert_equal 3, @business.user_accounts.count
    end

    test "does not remove member from the business if they are members of any other org in the business" do
      org2 = create :organization, plan: GitHub::Plan.business_plus, seats: 10
      org2.add_member(@member)
      perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
        @business.add_organization(org2)
      end

      assert_equal 4, @business.user_accounts.count

      @org.remove_member!(@member)
      assert_equal 4, @business.user_accounts.count
    end

    test "does not remove business user accounts of members that are business administrators" do
      @org.add_member @admin

      expected_members = [*@org.admins, @member, @admin]
      assert_same_elements expected_members.map(&:id), @business.user_accounts.pluck(:user_id)

      @org.remove_member! @admin

      expected_members = [*@org.admins, @member, @admin]
      assert_same_elements expected_members.map(&:id), @business.user_accounts.pluck(:user_id)
    end
  end
end
