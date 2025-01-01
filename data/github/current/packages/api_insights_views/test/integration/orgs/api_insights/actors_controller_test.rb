# typed: true
# frozen_string_literal: true

require "test_helper"

module Orgs
  module ApiInsights
    class ActorsControllerTest < GitHub::IntegrationTestCase

      include HydroTestHelpers
      include DogstatsTestHelpers
      include GitHub::ReactPayloadHelper
      include FineGrainedPermissionsTestHelper

      fixtures do
        @owner = create(:user)
        @member = create(:user)
        @rando = create(:user)
        @business = create(:business, :metered_ghec)
        @org = create(:organization, admin: @owner, business: @business)
        @user_app = create :oauth_application, user: @owner
        @org_app = create :oauth_application, user: @org
        @oauth_access = create(:oauth_access, application: @org_app, user: @owner)
        @user_oauth_access = create(:oauth_access, application: @user_app, user: @member)

        @integration = create(:integration, :with_marketplace_listing, owner: @org)
        @gh_app_access = @integration.grant(@member)
        @installation = create(:integration_installation, integration: @integration, target: @org)
      end

      setup do
        GitHub.flipper[:api_insights].enable
        GitHub.flipper[:api_insights_owner_bypass].disable
        GitHub.flipper[:api_insights_async].disable
        @org.add_member(@member)

        @requestor_has_activity = { "subject_id" => @owner.id, "subject_name" => @owner.display_login, "actor_id" => @oauth_access.id, "actor_name" => "VSCode" }
        @data = Kusto::Data::Dataset.new [{
          "FrameType" => "DataTable",
          "TableId" => 1,
          "TableName" => "PrimaryResult",
          "TableKind" => "PrimaryResult",
          "Columns" => [
            { "ColumnName" => "actor_id", "ColumnType" => "int" },
            { "ColumnName" => "actor_name", "ColumnType" => "string" },
            { "ColumnName" => "subject_id", "ColumnType" => "int" },
            { "ColumnName" => "subject_name", "ColumnType" => "string" },
            { "ColumnName" => "total_request_count", "ColumnType" => "int" },
            { "ColumnName" => "rate_limited_request_count", "ColumnType" => "int" },

          ],
          "Rows" => [[@oauth_access.id, "VSCode", @owner.id, @owner.display_login, 100, 10]]
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
        ActorsController.any_instance.stubs(:futures).returns(
          [
            Concurrent::Promises.future { @requestor_has_activity },
            Concurrent::Promises.future { ::ApiInsights::Stats::StatsResult.new(@data) },
          ]
        )

        @user_actor_has_activity = { "subject_id" => @owner.id, "subject_name" => @owner.display_login, "actor_id" => @user_oauth_access.id, "actor_name" => "User App" }
        @user_actor_data = Kusto::Data::Dataset.new [{
          "FrameType" => "DataTable",
          "TableId" => 1,
          "TableName" => "PrimaryResult",
          "TableKind" => "PrimaryResult",
          "Columns" => [
            { "ColumnName" => "actor_id", "ColumnType" => "int" },
            { "ColumnName" => "actor_name", "ColumnType" => "string" },
            { "ColumnName" => "subject_id", "ColumnType" => "int" },
            { "ColumnName" => "subject_name", "ColumnType" => "string" },
            { "ColumnName" => "total_request_count", "ColumnType" => "int" },
            { "ColumnName" => "rate_limited_request_count", "ColumnType" => "int" },

          ],
          "Rows" => [[@user_oauth_access.id, "User App", @owner.id, @owner.display_login, 100, 10]]
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

        @gh_app_actor_has_activity = { "subject_id" => @owner.id, "subject_name" => @owner.display_login, "actor_id" => @gh_app_access.id, "actor_name" => "GH App" }
        @gh_app_actor_data = Kusto::Data::Dataset.new [{
          "FrameType" => "DataTable",
          "TableId" => 1,
          "TableName" => "PrimaryResult",
          "TableKind" => "PrimaryResult",
          "Columns" => [
            { "ColumnName" => "actor_id", "ColumnType" => "int" },
            { "ColumnName" => "actor_name", "ColumnType" => "string" },
            { "ColumnName" => "subject_id", "ColumnType" => "int" },
            { "ColumnName" => "subject_name", "ColumnType" => "string" },
            { "ColumnName" => "total_request_count", "ColumnType" => "int" },
            { "ColumnName" => "rate_limited_request_count", "ColumnType" => "int" },

          ],
          "Rows" => [[@gh_app_access.id, "GH App", @owner.id, @owner.display_login, 100, 10]]
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
      end

      if !GitHub.single_tenant_enterprise?
        test "returns 404 when actor type does not match known types" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/foo_type/1234"
          assert_response_not_found
        end

        test "does not display when actor id has no activity in org" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/oauth_app/3456"

          assert_response_not_found
        end

        test "does not display if actor does not belong to user" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@member.id}/actors/oauth_app/#{@oauth_access.id}"

          assert_response_not_found
        end

        test "preload all flags" do
          as @owner
          assert_all_features_preloaded do
            get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/oauth_app/#{@oauth_access.id}"
          end
          assert_response_success
        end

        test "displays for an actor type of oauth_app" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/oauth_app/#{@oauth_access.id}"

          assert_response_success
        end

        test "display for an actor of type oauth_app when has recent activity but app is missing" do
          requestor_has_activity = { "subject_id" => @owner.id, "subject_name" => @owner.display_login, "actor_id" => 54321, "actor_name" => "VSCode" }
          ActorsController.any_instance.stubs(:futures).returns(
            [
              Concurrent::Promises.future { requestor_has_activity },
            ]
          )
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/oauth_app/54321"

          assert_response_success
        end

        test "404s when an actor of type oauth_app has no recent activity and app is missing" do
          requestor_has_activity = { "subject_id" => @owner.id, "subject_name" => @owner.display_login, "actor_id" => 54321, "actor_name" => "VSCode" }
          ActorsController.any_instance.stubs(:futures).returns(
            [
              Concurrent::Promises.future { requestor_has_activity },
            ]
          )
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/oauth_app/654321"

          assert_response_not_found
        end

        test "displays for an actor type of classic_pat" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/classic_pat/#{@oauth_access.id}"

          assert_response_success
        end

        test "Classic pat displays user profile name in breadcrumb instead of token name" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/classic_pat/#{@oauth_access.id}"

          assert_react_payload_equal [:breadcrumb, :actor_name], @owner.safe_profile_name, :page_payload, false
          assert_react_payload_equal [:breadcrumb, :label], "Personal access token (classic)", :page_payload, false
          assert_response_success
        end

        test "displays for an actor type of fine_grained_pat" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/fine_grained_pat/#{@oauth_access.id}"

          assert_response_success
        end

        test "Other actors display actor name in breadcrumb" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/fine_grained_pat/#{@oauth_access.id}"

          assert_react_payload_equal [:breadcrumb, :actor_name], "VSCode", :page_payload, false
          assert_react_payload_equal [:breadcrumb, :label], "Fine-grained personal access token", :page_payload, false

          assert_response_success
        end

        test "displays for an actor type of github_app_user_to_server" do
          ActorsController.any_instance.stubs(:futures).returns(
            [
              Concurrent::Promises.future { @gh_app_actor_has_activity },
              Concurrent::Promises.future { ::ApiInsights::Stats::StatsResult.new(@gh_app_actor_data) },
            ]
          )
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/github_app_user_to_server/#{@gh_app_access.id}"

          assert_response_success
          assert_react_payload_equal [:actor_stats, :request_count], "100", :page_payload, false
          assert_react_payload_equal [:actor_stats, :rate_limited_request_count], "10", :page_payload, false
          assert_react_payload_equal [:actor_stats, :current_limit], "15k", :page_payload, false
        end

        test "emits an error if oauth access exists but has no integration" do
          ActorsController.any_instance.stubs(:futures).returns(
            [
              Concurrent::Promises.future { @gh_app_actor_has_activity },
              Concurrent::Promises.future { ::ApiInsights::Stats::StatsResult.new(@gh_app_actor_data) },
            ]
          )
          OauthAccess.any_instance.stubs(:integration).returns(nil)
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/github_app_user_to_server/#{@gh_app_access.id}"

          assert_response_success
          assert_react_payload_equal [:actor_stats, :request_count], "100", :page_payload, false
          assert_react_payload_equal [:actor_stats, :rate_limited_request_count], "10", :page_payload, false
          assert_react_payload_nil [:actor_stats, :current_limit], :page_payload, false
          report = Failbot.reports.last
          assert_equal "Orgs::ApiInsights::ActorsController::OauthAccessMissingIntegration", Failbot.exception_classname_from_hash(report)
          assert_equal "Integration is nil for oauth access #{@gh_app_access.id}", Failbot.exception_message_from_hash(report)
        end

        test "does not 404 if has recent activity and app is missing" do
          requestor_has_activity = { "subject_id" => @owner.id, "subject_name" => @owner.display_login, "actor_id" => 123456, "actor_name" => "GH App" }
          ActorsController.any_instance.stubs(:futures).returns(
            [
              Concurrent::Promises.future { requestor_has_activity },
            ]
          )
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/github_app_user_to_server/123456"

          assert_response_success
        end

        test "404s if has no recent information and app is missing" do
          requestor_has_activity = { "subject_id" => @owner.id, "subject_name" => @owner.display_login, "actor_id" => 123456, "actor_name" => "GH App" }
          ActorsController.any_instance.stubs(:futures).returns(
            [
              Concurrent::Promises.future { requestor_has_activity },
            ]
          )
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/github_app_user_to_server/1234567"

          assert_response_not_found
        end

        test "does not display for non-admins" do
          as @rando
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/oauth_app/#{@oauth_access.id}"
          assert_response_not_found
        end

        test "does not display for members who are not admins" do
          as @member
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/oauth_app/#{@oauth_access.id}"
          assert_response_not_found
        end

        test "displays for member when given custom role with view_org_api_insights FGP" do
          role = create_custom_org_role(owner: @org, role_description: "Test API Insights Role", fgps: [:view_org_api_insights], base_role: nil)
          granter = ::Permissions::Granters::RoleGranter.new(actor: @member, target: @org, role: role)
          result = granter.grant_unless_exists!

          as @member
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/oauth_app/#{@oauth_access.id}"
          assert_response_success
        end

        test "does not display if user does not exist" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/doesnotexist/actors/github_app_user_to_server/1234"

          assert_response_not_found
        end

        test "does not display if user is not a member of the org" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@rando.id}"
          assert_response_not_found
        end

        test "does not display when FF is disabled" do
          GitHub.flipper[:api_insights].disable
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/oauth_app/#{@oauth_access.id}"
          assert_response_not_found
        end

        test "instruments index" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/oauth_app/#{@oauth_access.id}"
          assert_response_success
          message = {
            category: "api_insights",
            action: "api_insights_view",
            label: "organization_id:#{@org.id};period:24h;t:UTC;interval:1h;type:all;requests:all;p:1;tr:desc;",
          }
          assert_hydro_published_partial message, schema: "github.analytics.v0.Event"
          assert_dogstats_increment(1, "api_insights_controllers.kusto_query", tags: ["success:true"])
        end

        test "404s if summary result is nil" do
          ActorsController.any_instance.stubs(:futures).returns(
            [
              Concurrent::Promises.future { nil },
            ]
          )
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/oauth_app/#{@oauth_access.id}"
          assert_response_not_found
        end

        test "shows an error when an unknown error occurs" do
          ActorsController.any_instance.stubs(:futures).returns(
            [
              Concurrent::Promises.future { @requestor_has_activity },
              Concurrent::Promises.future { ::ApiInsights::Stats::StatsResult.new(@data) },
              Concurrent::Promises.future { raise StandardError.new("boom!") }
            ]
          )
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/oauth_app/#{@oauth_access.id}"
          assert_response_success
          assert_react_payload_equal [:error], "Failed to load API insights data"
          assert_dogstats_increment(1, "api_insights_controllers.kusto_query", tags: ["success:false"])
        end

        test "shows a kusto error when kusto query fails" do
          error = ::ApiInsights::Stats::Error.new(::ApiInsights::Stats::ErrorCode::PAGER_INVALID_PAGE, allowed_min_value: 1)
          ActorsController.any_instance.stubs(:futures).returns(
            [
              Concurrent::Promises.future { @requestor_has_activity },
              Concurrent::Promises.future { ::ApiInsights::Stats::StatsResult.new(@data) },
              Concurrent::Promises.future { raise error }
            ]
          )
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/oauth_app/#{@oauth_access.id}"
          assert_response_success
          assert_react_payload_equal [:error], error.code.to_error_message
          assert_dogstats_increment(1, "api_insights_controllers.kusto_query", tags: ["success:false"])
        end

        test "actor_stats has correct limit for org owned oauth_app" do
          requestor_has_activity = { "subject_id" => @owner.id, "subject_name" => @owner.display_login, "actor_id" => @oauth_access.id, "actor_name" => @org_app.name }
          data = Kusto::Data::Dataset.new [{
            "FrameType" => "DataTable",
            "TableId" => 1,
            "TableName" => "PrimaryResult",
            "TableKind" => "PrimaryResult",
            "Columns" => [
              { "ColumnName" => "actor_id", "ColumnType" => "int" },
              { "ColumnName" => "actor_name", "ColumnType" => "string" },
              { "ColumnName" => "subject_id", "ColumnType" => "int" },
              { "ColumnName" => "subject_name", "ColumnType" => "string" },
              { "ColumnName" => "total_request_count", "ColumnType" => "int" },
              { "ColumnName" => "rate_limited_request_count", "ColumnType" => "int" },

            ],
            "Rows" => [[@oauth_access.id, @org_app.name, @owner.id, @owner.id, 100, 10]]
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
          ActorsController.any_instance.stubs(:futures).returns(
            [
              Concurrent::Promises.future { requestor_has_activity },
              Concurrent::Promises.future { ::ApiInsights::Stats::StatsResult.new(data) },
            ]
          )
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/oauth_app/#{@oauth_access.id}"
          assert_response_success
          assert_react_payload_equal [:actor_stats, :request_count], "100", :page_payload, false
          assert_react_payload_equal [:actor_stats, :rate_limited_request_count], "10", :page_payload, false
          assert_react_payload_equal [:actor_stats, :current_limit], "5k", :page_payload, false
        end

        test "actor_stats has correct limit for user owned oauth_app" do
          requestor_has_activity = { "subject_id" => @owner.id, "subject_name" => @owner.display_login, "actor_id" => @user_oauth_access.id, "actor_name" => @user_app.name }
          data = Kusto::Data::Dataset.new [{
            "FrameType" => "DataTable",
            "TableId" => 1,
            "TableName" => "PrimaryResult",
            "TableKind" => "PrimaryResult",
            "Columns" => [
              { "ColumnName" => "actor_id", "ColumnType" => "int" },
              { "ColumnName" => "actor_name", "ColumnType" => "string" },
              { "ColumnName" => "subject_id", "ColumnType" => "int" },
              { "ColumnName" => "subject_name", "ColumnType" => "string" },
              { "ColumnName" => "total_request_count", "ColumnType" => "int" },
              { "ColumnName" => "rate_limited_request_count", "ColumnType" => "int" },

            ],
            "Rows" => [[@user_oauth_access.id, @user_app.name, @owner.id, @owner.display_login, 100, 10]]
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
          ActorsController.any_instance.stubs(:futures).returns(
            [
              Concurrent::Promises.future { requestor_has_activity },
              Concurrent::Promises.future { ::ApiInsights::Stats::StatsResult.new(data) },
            ]
          )
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/oauth_app/#{@user_oauth_access.id}"
          assert_response_success
          assert_react_payload_equal [:actor_stats, :request_count], "100", :page_payload, false
          assert_react_payload_equal [:actor_stats, :rate_limited_request_count], "10", :page_payload, false
          assert_react_payload_equal [:actor_stats, :current_limit], "5k", :page_payload, false
        end

        test "actor_stats has correct limit for other actor types" do
          ActorsController.any_instance.stubs(:futures).returns(
            [
              Concurrent::Promises.future { @user_actor_has_activity },
              Concurrent::Promises.future { ::ApiInsights::Stats::StatsResult.new(@user_actor_data) },
            ]
          )
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/fine_grained_pat/#{@user_oauth_access.id}"
          assert_response_success
          assert_react_payload_equal [:actor_stats, :request_count], "100", :page_payload, false
          assert_react_payload_equal [:actor_stats, :rate_limited_request_count], "10", :page_payload, false
          assert_react_payload_equal [:actor_stats, :current_limit], "5k", :page_payload, false
        end
      end

      if GitHub.single_tenant_enterprise?
        test "does not display for single tenant enterprise" do
          as @owner
          get "/orgs/#{@org.display_login}/insights/api/users/#{@owner.id}/actors/oauth_app/#{@oauth_access.id}"

          assert_response_not_found
        end
      end
    end
  end
end
