# typed: true
# frozen_string_literal: true

require "test_helper"

class Organization::ApiInsightsDependencyTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    @owner = create(:user)
    @member = create(:user)
    @rando = create(:user)
    @business = create(:business, :metered_ghec)
    @org = create(:organization, admin: @owner, business: @business)
  end

  setup do
    @org.add_member(@member, action: :write)
  end

  if !GitHub.single_tenant_enterprise?
    context "api_insights_enabled?" do

      test "returns true when enabled" do
        assert @org.api_insights_enabled?(@owner)
      end

      test "returns false when not a member of the org" do
        refute @org.api_insights_enabled?(@rando)
      end

      test "returns false for non-admin members" do
        refute @org.api_insights_enabled?(@member)
      end

      test "returns false when logged out" do
        refute @org.api_insights_enabled?(nil)
      end

      test "returns true when a member is given a custom role with view_org_api_insights FGP" do
        refute @org.api_insights_enabled?(@member)

        role = create_custom_org_role(owner: @org, role_description: "Test API Insights Role", fgps: [:view_org_api_insights], base_role: nil)
        granter = Permissions::Granters::RoleGranter.new(actor: @member, target: @org, role: role)
        result = granter.grant_unless_exists!

        assert @org.api_insights_enabled?(@member)
      end

    end
  end

  if GitHub.single_tenant_enterprise?
    test "does not display for single tenant enterprise" do
      refute @org.api_insights_enabled?(@owner)
    end
  end
end
