# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.enterprise?
  class OrganizationConfigurableDefaultOrganizationMembershipVisibilityTest < GitHub::TestCase
    fixtures do
      @org = create :organization
      @user = create :user
    end

    test "added org members are concealed when default visibility is private" do
      GitHub.stubs(:default_org_membership_visibility_public?).returns(false)
      @org.add_member(@user)
      refute @org.public_member?(@user)
    end

    test "added team members are concealed when default visibility is private" do
      GitHub.stubs(:default_org_membership_visibility_public?).returns(false)
      create(:team, organization: @org).add_member(@user)
      refute @org.public_member?(@user)
    end

    test "added org owners are concealed when default visibility is private" do
      GitHub.stubs(:default_org_membership_visibility_public?).returns(false)
      @org.add_admin(@user)
      refute @org.public_member?(@user)
    end

    test "added org members are publicised when default visibility is public" do
      GitHub.stubs(:default_org_membership_visibility_public?).returns(true)
      @org.add_member(@user)
      assert @org.public_member?(@user)
    end

    test "added team members are publicised when default visibility is public" do
      GitHub.stubs(:default_org_membership_visibility_public?).returns(true)
      create(:team, organization: @org).add_member(@user)
      assert @org.public_member?(@user)
    end

    test "added org owners are publicised when default visibility is public" do
      GitHub.stubs(:default_org_membership_visibility_public?).returns(true)
      @org.add_admin(@user)
      assert @org.public_member?(@user)
    end
  end
end
