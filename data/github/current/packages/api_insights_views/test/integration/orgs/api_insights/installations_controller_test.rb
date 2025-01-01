# typed: true
# frozen_string_literal: true

require "test_helper"

module Orgs
  module ApiInsights
    class InstallationsControllerTest < GitHub::IntegrationTestCase

      include HydroTestHelpers
      include GitHub::ReactPayloadHelper
      include FineGrainedPermissionsTestHelper
      include GitHub::ReactPayloadHelper

      fixtures do
        @owner = create(:user)
        @member = create(:user)
        @rando = create(:user)
        @staff = create :staff_admin_user
        @business = create(:business, :metered_ghec)
        @org = create(:organization, admin: @owner, business: @business)

        @org_2 = create(:organization, admin: @owner, business: @business)

        @integration  = create(:integration, :with_marketplace_listing)
        @installation = create(:integration_installation, integration: @integration, target: @org)
        @installation_2 = create(:integration_installation, integration: @integration, target: @org_2)
      end

      setup do
        GitHub.flipper[:api_insights].enable
        GitHub.flipper[:api_insights_owner_bypass].disable
        GitHub.flipper[:api_insights_async].disable
        @org.add_member(@member)
        @requestor_has_activity = { "actor_id" => @installation.id, "actor_name" => "Slack" }
        @data = Kusto::Data::Dataset.new [{
          "FrameType" => "DataTable",
          "TableId" => 1,
          "TableName" => "PrimaryResult",
          "TableKind" => "PrimaryResult",
          "Columns" => [
            { "ColumnName" => "actor_id", "ColumnType" => "int" },
            { "ColumnName" => "actor_name", "ColumnType" => "string" },
            { "ColumnName" => "total_request_count", "ColumnType" => "int" },
            { "ColumnName" => "rate_limited_request_count", "ColumnType" => "int" },

          ],
          "Rows" => [[@installation.id, "Slack", 100, 10]]
        }, {
          "FrameType": "DataTable",
          "TableId": 2,
          "TableKind": "QueryCompletionInformation",
          "TableName": "QueryCompletionInformation",
          "Columns": [{
            "ColumnName": "Timestamp",
            "ColumnType": "datetime"
          }],
          "Rows": [[Time.now.utc]]
        }]
        InstallationsController.any_instance.stubs(:futures).returns(
          [
            Concurrent::Promises.future { @requestor_has_activity },
            Concurrent::Promises.future { ::ApiInsights::Stats::StatsResult.new(@data) }
          ]
        )
      end

      if !GitHub.single_tenant_enterprise?
        test "preload all flags" do
          as @owner
          assert_all_features_preloaded do
            get "/orgs/#{@org.display_login}/insights/api/installations/#{@installation.id}"
          end
          assert_response_success
        end

        test "displays the installations api insights page (shows apps that represent itself)" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/installations/#{@installation.id}"
          assert_response_success
        end

        test "does not display when the installation is not for this org" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/installations/#{@installation_2.id}"
          assert_response_not_found
        end

        test "does display when installation has recent activity for this org" do
          requestor_has_activity = { "actor_id" => 123456, "actor_name" => "Slack" }
          InstallationsController.any_instance.stubs(:futures).returns(
            [
              Concurrent::Promises.future { requestor_has_activity },
            ]
          )
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/installations/123456"
          assert_response_success
        end

        test "does not display when installation has no recent activity for this org" do
          requestor_has_activity = { "actor_id" => 123456, "actor_name" => "Slack" }
          InstallationsController.any_instance.stubs(:futures).returns(
            [
              Concurrent::Promises.future { requestor_has_activity },
            ]
          )

          as @owner
          get "/orgs/#{@org.display_login}/insights/api/installations/1234567"
          assert_response_not_found
        end

        test "does not display for non-admins" do
          as @rando
          get "/orgs/#{@org.display_login}/insights/api/installations/#{@installation.id}"
          assert_response_not_found
        end

        test "does not display for members who are not admins" do
          as @member
          get "/orgs/#{@org.display_login}/insights/api/installations/#{@installation.id}"
          assert_response_not_found
        end

        test "displays for member when given custom role with view_org_api_insights FGP" do
          role = create_custom_org_role(owner: @org, role_description: "Test API Insights Role", fgps: [:view_org_api_insights], base_role: nil)
          granter = ::Permissions::Granters::RoleGranter.new(actor: @member, target: @org, role: role)
          result = granter.grant_unless_exists!

          as @member
          get "/orgs/#{@org.display_login}/insights/api/installations/#{@installation.id}"
          assert_response_success
        end

        test "does not display when FF is disabled" do
          GitHub.flipper[:api_insights].disable
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/installations/#{@installation.id}"
          assert_response_not_found
        end

        if !GitHub.multi_tenant_enterprise?
          test "bypass non-staff returns 404" do
            GitHub.flipper[:api_insights_owner_bypass].enable(@member)
            as @member
            get "/orgs/#{@org.display_login}/insights/api/installations/#{@installation.id}"
            assert_response 404
          end

          test "bypass staff returns 200" do
            GitHub.flipper[:api_insights_owner_bypass].enable(@staff)
            as @staff
            get "/orgs/#{@org.display_login}/insights/api/installations/#{@installation.id}"
            assert_response 200
          end

          test "bypass staff returns 404 when FF disabled" do
            GitHub.flipper[:api_insights_owner_bypass].disable(@staff)
            as @staff
            get "/orgs/#{@org.display_login}/insights/api/installations/#{@installation.id}"
            assert_response 404
          end
        end

        test "instruments index" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/installations/#{@installation.id}"
          assert_response_success
          message = {
            category: "api_insights",
            action: "api_insights_view",
            label: "organization_id:#{@org.id};period:24h;t:UTC;interval:1h;type:all;requests:all;p:1;tr:desc;",
          }
          assert_hydro_published_partial message, schema: "github.analytics.v0.Event"
        end

        test "shows an error when an unknown error occurs" do
          InstallationsController.any_instance.stubs(:futures).returns(
            [
              Concurrent::Promises.future { @requestor_has_activity },
              Concurrent::Promises.future { ::ApiInsights::Stats::StatsResult.new(@data) },
              Concurrent::Promises.future { raise StandardError.new("boom!") }
            ]
          )
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/installations/#{@installation.id}"
          assert_response_success
          assert_react_payload_equal [:error], "Failed to load API insights data"
        end

        test "shows a kusto error when kusto query fails" do
          error = ::ApiInsights::Stats::Error.new(::ApiInsights::Stats::ErrorCode::PAGER_INVALID_PAGE, allowed_min_value: 1)
          InstallationsController.any_instance.stubs(:futures).returns(
            [
              Concurrent::Promises.future { @requestor_has_activity },
              Concurrent::Promises.future { ::ApiInsights::Stats::StatsResult.new(@data) },
              Concurrent::Promises.future { raise error }
            ]
          )
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/installations/#{@installation.id}"
          assert_response_success
          assert_react_payload_equal [:error], error.code.to_error_message
        end

        test "can fetch the right rate limit for installation_stats" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/installations/#{@installation.id}"
          assert_response_success

          assert_equal @installation.rate_limit, 5000
          assert_react_payload_equal [:installation_stats, :request_count], "100", :page_payload, false
          assert_react_payload_equal [:installation_stats, :rate_limited_request_count], "10", :page_payload, false
          # GHEC overrides the installation rate limit to 15k
          assert_react_payload_equal [:installation_stats, :current_limit], "15k", :page_payload, false
        end
      end

      if GitHub.single_tenant_enterprise?
        test "does not display for single tenant enterprise" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/installations/#{@installation.id}"
          assert_response_not_found
        end
      end
    end
  end
end
