# typed: true
# frozen_string_literal: true

require "test_helper"

module Orgs
  module ApiInsights
    class SummaryControllerTest < GitHub::IntegrationTestCase

      include HydroTestHelpers
      include GitHub::ReactPayloadHelper
      include FineGrainedPermissionsTestHelper

      fixtures do
        @owner = create :user
        @rando = create :user
        @member = create :user
        @staff = create :staff_admin_user
        @business = create(:business, :metered_ghec)
        @org = create(:organization, admin: @owner, business: @business)
      end

      setup do
        @org.add_member(@member)
      end

      if !GitHub.single_tenant_enterprise?
        test "preload all flags" do
          as @owner
          assert_all_features_preloaded do
            get "/orgs/#{@org.display_login}/insights/api"
          end
          assert_response_success
        end

        test "displays the rate limit insights page" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api"
          assert_response_success
        end

        test "does not display for non-admins" do
          as @member
          get "/orgs/#{@org.display_login}/insights/api"
          assert_response_not_found
        end

        test "displays for member when given custom role with view_org_api_insights FGP" do
          role = create_custom_org_role(owner: @org, role_description: "Test API Insights Role", fgps: [:view_org_api_insights], base_role: nil)
          granter = ::Permissions::Granters::RoleGranter.new(actor: @member, target: @org, role: role)
          result = granter.grant_unless_exists!

          as @member
          get "/orgs/#{@org.display_login}/insights/api"
          assert_response_success
        end

        test "instruments index" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api?period=7d"
          assert_response_success
          message = {
            category: "api_insights",
            action: "api_insights_view",
            label: "organization_id:#{@org.id};period:7d;t:UTC;interval:1h;type:all;requests:all;p:1;tr:desc;",
          }
          assert_hydro_published_partial message, schema: "github.analytics.v0.Event"
        end

        test "shows an error when kusto query fails" do
          SummaryController.any_instance.stubs(:futures).returns(
            [Concurrent::Promises.future { raise StandardError.new("boom!") }]
          )
          as @owner
          get "/orgs/#{@org.display_login}/insights/api?period=7d"
          assert_response_success
          assert_react_payload_equal [:error], "Failed to load API insights data"
        end

        test "shows a kusto error when kusto query fails" do
          error = ::ApiInsights::Stats::Error.new(::ApiInsights::Stats::ErrorCode::PAGER_INVALID_PAGE, allowed_min_value: 1)
          SummaryController.any_instance.stubs(:futures).returns(
            [Concurrent::Promises.future { raise error }]
          )
          as @owner
          get "/orgs/#{@org.display_login}/insights/api?period=7d"
          assert_response_success
          assert_react_payload_equal [:error], error.code.to_error_message
        end
      end

      if GitHub.single_tenant_enterprise?
        test "does not display for single tenant enterprise" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api"
          assert_response_not_found
        end
      end
    end
  end
end
