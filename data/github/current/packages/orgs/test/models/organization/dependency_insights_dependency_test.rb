# typed: true
# frozen_string_literal: true

require "test_helper"

class Organization::DependencyInsightsDependencyTest < GitHub::TestCase
  include AuthenticationHelpers

  fixtures do
    @rando = create(:user)
    @owner = create(:user, login: "owner")
    @member = create(:user, login: "member")
    @org = create(:business_plus_organization, admin: @owner, login: "foo")
    @non_business_org = create(:organization, admin: @owner)
  end

  setup do
    @org.add_member(@member)
  end

  if !GitHub.single_tenant_enterprise?
    context "dependency_insights_enabled_for?" do
      test "returns false for anon" do
        refute @org.dependency_insights_enabled_for?(nil)
      end

      test "returns false for non admin" do
        refute @org.dependency_insights_enabled_for?(@rando)
      end

      test "returns true for admin" do
        assert @org.dependency_insights_enabled_for?(@owner)
      end

      test "returns true for member" do
        assert @org.dependency_insights_enabled_for?(@member)
      end

      test "returns false if members are not allowed to view" do
        @org.disallow_members_can_view_dependency_insights(actor: @owner)
        refute @org.dependency_insights_enabled_for?(@member)
      end

      if !GitHub.multi_tenant_enterprise?
        test "returns false for non-business org" do
          refute @non_business_org.dependency_insights_enabled_for?(@owner)
        end
      end
    end
  end

  if !GitHub.single_or_multi_tenant_enterprise?
    context "dependency_insights_visible?" do
      test "returns false for anon" do
        refute @org.dependency_insights_visible?(nil)
      end

      test "returns false for non admin" do
        refute @org.dependency_insights_visible?(@rando)
      end

      test "returns true for admin" do
        assert @org.dependency_insights_visible?(@owner)
      end

      test "returns true for member" do
        assert @org.dependency_insights_visible?(@member)
      end

      test "returns false if members are not allowed to view" do
        @org.disallow_members_can_view_dependency_insights(actor: @owner)
        refute @org.dependency_insights_visible?(@member)
      end

      test "returns false for non-business org" do
        refute @non_business_org.dependency_insights_visible?(@owner)
      end
    end
  end

  if GitHub.single_tenant_enterprise?
    test "dependency_insights_enabled_for? returns false in single tenant" do
      refute @org.dependency_insights_enabled_for?(@owner)
    end

    test "dependency_insights_visible? returns false in single tenant" do
      refute @org.dependency_insights_visible?(@owner)
    end
  end

  if GitHub.multi_tenant_enterprise?
    test "dependency_insights_enabled_for? returns true in multi tenant" do
      assert @org.dependency_insights_enabled_for?(@owner)
    end

    test "dependency_insights_visible? returns false in multi tenant" do
      refute @org.dependency_insights_visible?(@owner)
    end
  end
end
