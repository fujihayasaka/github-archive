# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../../orca_test_helpers"

class Orgs::CopilotSettings::CustomModelTrainingsControllerTest < GitHub::IntegrationTestCase
  include CopilotTestHelper
  include ConditionalAccess::FilterTestHelper
  include GitHub::ReactPayloadHelper
  include OrcaTestHelpers

  fixtures do
    enable_feature_flag(:orca_override_training_rate_limit)

    @admin = create(:user)
    @test_base_url = "http://example.com/twirp"
    @test_hmac_key = "key"

    @org = create(:copilot_for_business_enabled_organization, admin: @admin)
    @org_owned_repo = create(:private_repository, owner: @org, from_example: :post_receive_job_test)
    @org_owned_repo2 = create(:private_repository, owner: @org, from_example: :language_test)

    @repo_from_different_user = create(:private_repository)
    @pipeline_id = SecureRandom.uuid

    @repositories = [@org_owned_repo, @org_owned_repo2].sort_by(&:id)
    @languages = %w[JavaScript Ruby]
  end

  setup do
    @under_rate_limit = GitHub::Orca::RateLimitDetails.new(is_rate_limited: false)
    @rate_limited = GitHub::Orca::RateLimitDetails.new(is_rate_limited: true)
    @org_pipeline = Orca::Pipeline.new(
      orca_pipeline_details(
          pipeline_id: @pipeline_id,
          organization: @org,
          repositories: [@org_owned_repo],
          languages: @languages,
        )
      )
    enable_feature_flag(:copilot_custom_models, @admin)
  end

  context "#show" do
    test "404s if feature flag is not set" do
      disable_feature_flag(:copilot_custom_models, @admin)

      as @admin
      get "/organizations/#{@org.display_login}/settings/copilot/custom_model/training/#{@pipeline_id}"

      assert_response :not_found
    end

    # EMU factory for organizations has access to Copilot (`organization.has_copilot_for_business?` returns `true`)
    # so can be skipped
    test "404s if org does not have access to Copilot", skip_with_all_emus: true do
      org_without_copilot = create(:organization)
      admin = org_without_copilot.admins.first
      enable_feature_flag(:copilot_custom_models, admin)
      create(:repository, owner: org_without_copilot, from_example: :post_receive_job_test)

      as admin
      get "/organizations/#{org_without_copilot.display_login}/settings/copilot/custom_model/training/#{@pipeline_id}"

      assert_response :not_found
    end

    # EMUs need to be logged in for an EMU test to test anything EMU specific, so we can skip it
    test "404s if not logged in", skip_with_all_emus: true do
      get "/organizations/#{@org.display_login}/settings/copilot/custom_model/training/#{@pipeline_id}"

      assert_response :not_found
    end

    test "include the basic pipeline data in the react payload" do
      Orca::Pipeline.stubs(:fetch_by_id).returns(@org_pipeline)
      Orca::Pipeline.stubs(:latest_pipeline).returns(@org_pipeline)
      Orca::Pipeline.stubs(:latest_completed_pipeline).returns(@org_pipeline)
      Orca::Client.any_instance.stubs(:get_rate_limit).returns(@under_rate_limit)
      as @admin
      get "/organizations/#{@org.display_login}/settings/copilot/custom_model/training/#{@pipeline_id}"

      assert_response :ok

      json_payload = get_react_embedded_json["payload"]
      json_p_req = json_payload["pipelineDetails"]
      assert_equal @pipeline_id, json_p_req["id"]
      assert_equal 1, json_p_req["repositoryCount"]

      assert_react_payload_equal(
        "editPath",
        settings_org_copilot_custom_models_edit_path(@org, @pipeline_id)
      )
    end

    test "404 if pipeline does not exist" do
      Orca::Pipeline.stubs(:fetch_by_id).returns(nil)
      as @admin
      assert_raises ActionController::RoutingError do
        get "/organizations/#{@org.display_login}/settings/copilot/custom_model/training/#{@pipeline_id}"
      end
    end
  end
end unless GitHub.enterprise?
