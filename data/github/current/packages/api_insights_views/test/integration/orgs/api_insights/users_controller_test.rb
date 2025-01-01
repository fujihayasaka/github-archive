# typed: true
# frozen_string_literal: true

require "test_helper"

module Orgs
  module ApiInsights
    class UsersControllerTest < GitHub::IntegrationTestCase

      include HydroTestHelpers
      include GitHub::ReactPayloadHelper
      include FineGrainedPermissionsTestHelper

      fixtures do
        @owner = create(:user)
        @member = create(:user)
        @rando = create(:user)
        @business = create(:business, :metered_ghec)
        @org = create(:organization, admin: @owner, business: @business)
      end

      setup do
        @org.add_member(@member)

        @requestor_has_activity = { "subject_id" => @member.id, "subject_name" => @member.display_login }
        @data = Kusto::Data::Dataset.new [{
          "FrameType" => "DataTable",
          "TableId" => 1,
          "TableName" => "PrimaryResult",
          "TableKind" => "PrimaryResult",
          "Columns" => [
            { "ColumnName" => "subject_id", "ColumnType" => "int" },
            { "ColumnName" => "subject_name", "ColumnType" => "string" },
            { "ColumnName" => "total_request_count", "ColumnType" => "int" },
            { "ColumnName" => "rate_limited_request_count", "ColumnType" => "int" },

          ],
          "Rows" => [[@member.id, @member.display_login, 100, 10]]
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
        UsersController.any_instance.stubs(:futures).returns(
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
            get "/orgs/#{@org.display_login}/insights/api/users/#{@member.id}"
          end
          assert_response_success
        end

        test "displays the users api insights page" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@member.id}"
          assert_response_success
        end

        test "displays the users api insights page with user id" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@member.id}"
          assert_response_success
        end

        context "default type param" do
          test "validates type" do
            as @owner
            get "/orgs/#{@org.display_login}/insights/api/users/#{@member.id}?type=foo"

            expected_values = {
              p: 1,
              tr: "desc",
              period: "24h",
              interval: "1h",
              type: "all",
              requests: "all",
              t: "UTC"
            }
            assert_equal expected_values, @controller.send(:default_page_params)
          end

          test "uses oauth_app type" do
            as @owner
            get "/orgs/#{@org.display_login}/insights/api/users/#{@member.id}?type=oauth_app"

            expected_values = {
              p: 1,
              tr: "desc",
              period: "24h",
              interval: "1h",
              type: "oauth_app",
              requests: "all",
              t: "UTC"
            }
            assert_equal expected_values, @controller.send(:default_page_params)
          end

          test "uses classic_pat type" do
            as @owner
            get "/orgs/#{@org.display_login}/insights/api/users/#{@member.id}?type=classic_pat"

            expected_values = {
              p: 1,
              tr: "desc",
              period: "24h",
              interval: "1h",
              type: "classic_pat",
              requests: "all",
              t: "UTC"
            }
            assert_equal expected_values, @controller.send(:default_page_params)
          end

          test "uses fine_grained_pat type" do
            as @owner
            get "/orgs/#{@org.display_login}/insights/api/users/#{@member.id}?type=fine_grained_pat"

            expected_values = {
              p: 1,
              tr: "desc",
              period: "24h",
              interval: "1h",
              type: "fine_grained_pat",
              requests: "all",
              t: "UTC"
            }
            assert_equal expected_values, @controller.send(:default_page_params)
          end

          test "uses github_app_user_to_server type" do
            as @owner
            get "/orgs/#{@org.display_login}/insights/api/users/#{@member.id}?type=github_app_user_to_server"

            expected_values = {
              p: 1,
              tr: "desc",
              period: "24h",
              interval: "1h",
              type: "github_app_user_to_server",
              requests: "all",
              t: "UTC"
            }
            assert_equal expected_values, @controller.send(:default_page_params)
          end
        end

        test "does not display for non-admins" do
          as @rando
          get "/orgs/#{@org.display_login}/insights/api/users/#{@member.id}"
          assert_response_not_found
        end

        test "does not display for members who are not admins" do
          as @member
          get "/orgs/#{@org.display_login}/insights/api/users/#{@member.id}"
          assert_response_not_found
        end

        test "displays for member when given custom role with view_org_api_insights FGP" do
          requestor_has_activity = { "subject_id" => @owner.id, "subject_name" => @owner.display_login }

          UsersController.any_instance.stubs(:futures).returns(
            [Concurrent::Promises.future { requestor_has_activity }]
          )
          role = create_custom_org_role(owner: @org, role_description: "Test API Insights Role", fgps: [:view_org_api_insights], base_role: nil)
          granter = ::Permissions::Granters::RoleGranter.new(actor: @member, target: @org, role: role)
          result = granter.grant_unless_exists!

          as @member
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}"
          assert_response_success
        end

        test "does not display if user does not exist" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/foobar"
          assert_response_not_found
        end

        test "does not display if user is not a member of the org" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@rando.id}"
          assert_response_not_found
        end

        test "instruments index" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@member.id}?type=fine_grained_pat"
          assert_response_success
          message = {
            category: "api_insights",
            action: "api_insights_view",
            label: "organization_id:#{@org.id};period:24h;t:UTC;interval:1h;type:fine_grained_pat;requests:all;p:1;tr:desc;",
          }
          assert_hydro_published_partial message, schema: "github.analytics.v0.Event"
        end

        test "shows an error when an unknown error occurs" do
          UsersController.any_instance.stubs(:futures).returns(
            [
              Concurrent::Promises.future { @requestor_has_activity },
              Concurrent::Promises.future { raise StandardError.new("boom!") }
            ]
          )
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@member.id}"
          assert_response_success
          assert_react_payload_equal [:error], "Failed to load API insights data"
        end

        test "shows a kusto error when kusto query fails" do
          error = ::ApiInsights::Stats::Error.new(::ApiInsights::Stats::ErrorCode::PAGER_INVALID_PAGE, allowed_min_value: 1)
          UsersController.any_instance.stubs(:futures).returns(
            [
              Concurrent::Promises.future { @requestor_has_activity },
              Concurrent::Promises.future { raise error }
            ]
          )
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@member.id}"
          assert_response_success
          assert_react_payload_equal [:error], error.code.to_error_message
        end
      end

      if GitHub.single_tenant_enterprise?
        test "does not display for single tenant enterprise" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@member.id}"
          assert_response_not_found
        end
      end
    end
  end
end
