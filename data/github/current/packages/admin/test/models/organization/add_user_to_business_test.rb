# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationAddUserToBusinessTest < GitHub::TestCase
  fixtures do
    @org = create :organization, plan: GitHub::Plan.business_plus, seats: 10
    @org2 = create :organization, plan: GitHub::Plan.business_plus, seats: 10
    @member = create(:user)
    @member2 = create(:user)
    @org.add_member(@member)
  end

  test "does not create business user accounts for single business environment" do
    GitHub.stubs(:single_business_environment?).returns(true)
    Business.delete_all
    business = create :business
    business.add_organization(@org)

    assert_equal business, @org.reload.business
    assert_equal 0, business.user_accounts.count

    @org.add_member(@member2)
    assert_equal 0, business.user_accounts.count
  end

  test "creates a business user account for a new org member who is not a member of any other organization in the business" do
    GitHub.stubs(:single_business_environment?).returns(false)
    business = create :business

    perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
      business.add_organization(@org)
      business.add_organization(@org2)
    end

    assert_equal business, @org.reload.business
    assert_equal 4, business.user_accounts.count

    @org.add_member(@member2)
    assert_equal 5, business.user_accounts.count
  end

  test "does not create a business user account for a new org member who is a member of any other organization in the business" do
    GitHub.stubs(:single_business_environment?).returns(false)
    business = create :business

    perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
      business.add_organization(@org)
      business.add_organization(@org2)
    end

    assert_equal business, @org.reload.business
    assert_equal business, @org2.reload.business
    assert_equal 4, business.user_accounts.count

    @org2.add_member(@member)
    assert_equal 4, business.user_accounts.count
  end
end
