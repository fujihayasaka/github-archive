# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../../orca_test_helpers"

class Orgs::CopilotSettings::CustomModelsControllerTest < GitHub::IntegrationTestCase
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

  context "#index" do
    test "renders react app with pipelines split by type and sorted" do
      deployed_pipeline_id = "deployed_pipeline_id"
      pipeline = Orca::Pipeline.new(
        GitHub::Orca::PipelineDetails.new(
          pipeline: GitHub::Orca::Pipeline.new(
            id: deployed_pipeline_id,
            organization: Orca::Client.organization(@org),
            created_at: 1.hour.ago.iso8601,
            completed_at: Time.current.iso8601,
            status: GitHub::Orca::PipelineStatus::PIPELINE_STATUS_COMPLETED,
            training_inputs: GitHub::Orca::PipelineTrainingInputs.new(
            language_filters: nil,
            repositories: @repositories.map do |repository|
                            GitHub::Orca::Repository.new(
                              id: repository.id,
                              name: repository.name,
                              clone_url: repository.clone_url,
                            )
                          end
            )
          )
        )
      )

      deployed_pipeline2_id = "deployed_pipeline2_id"
      pipeline2 = Orca::Pipeline.new(
        GitHub::Orca::PipelineDetails.new(
          pipeline: GitHub::Orca::Pipeline.new(
            id: deployed_pipeline2_id,
            organization: Orca::Client.organization(@org),
            created_at: 1.minute.ago.iso8601,
            completed_at: Time.current.iso8601,
            status: GitHub::Orca::PipelineStatus::PIPELINE_STATUS_COMPLETED,
            training_inputs: GitHub::Orca::PipelineTrainingInputs.new(
            language_filters: nil,
            repositories: @repositories.map do |repository|
                            GitHub::Orca::Repository.new(
                              id: repository.id,
                              name: repository.name,
                              clone_url: repository.clone_url,
                            )
                          end
            )
          )
        )
      )
      running_id = "running_id"
      running_pipeline = Orca::Pipeline.new(
        GitHub::Orca::PipelineDetails.new(
          pipeline: GitHub::Orca::Pipeline.new(
            id: running_id,
            created_at: Time.current.iso8601,
            organization: Orca::Client.organization(@org),
            status: GitHub::Orca::PipelineStatus::PIPELINE_STATUS_ENQUEUED,
            training_inputs: GitHub::Orca::PipelineTrainingInputs.new(
            repositories: @repositories.map do |repository|
                            GitHub::Orca::Repository.new(
                              id: repository.id,
                              name: repository.name,
                              clone_url: repository.clone_url,
                            )
                          end
            )
          )
        )
      )
      Orca::Pipeline.stubs(:get_pipelines).returns([pipeline, running_pipeline, pipeline2])
      Orca::Pipeline.stubs(:latest_completed_pipeline).returns(pipeline2)
      Orca::Pipeline.stubs(:latest_pipeline).returns(running_pipeline)
      Orca::Client.any_instance.stubs(:get_rate_limit).returns(@under_rate_limit)
      as @admin

      get "/organizations/#{@org.display_login}/settings/copilot/custom_models"
      assert_response :ok
      history = get_react_payload_value_from_keys("trainingHistory")
      deployed = get_react_payload_value_from_keys("deployedPipeline")
      pipelines = get_react_payload_value_from_keys("pipelines")
      assert_equal(pipelines.size, 3)
      assert_equal(pipelines.first["id"], running_id)
      assert_equal(pipelines.second["id"], deployed_pipeline2_id)
      assert_equal(pipelines.third["id"], deployed_pipeline_id)

      assert_equal(deployed["id"], deployed_pipeline2_id)
    end

    test "404s if flag is disabled" do
      disable_feature_flag(:copilot_custom_models, @admin)

      as @admin
      get "/organizations/#{@org.display_login}/settings/copilot/custom_models"

      assert_response :not_found
    end


    # EMU factory for organizations has access to Copilot (`organization.has_copilot_for_business?` returns `true`)
    # so can be skipped
    test "404s if org does not have access to Copilot", skip_with_all_emus: true do
      admin = create(:user)
      org_without_copilot = create(:organization, admin: admin)
      # Enable the feature, but the org does not have any Copilot licenses
      enable_feature_flag(:copilot_custom_models, org_without_copilot)
      enable_feature_flag(:copilot_custom_models, admin)

      as admin
      get "/organizations/#{org_without_copilot.display_login}/settings/copilot/custom_models"

      assert_response :not_found
    end

    # EMUs need to be logged in for an EMU test to test anything EMU specific, so we can skip it
    test "404s if not logged in", skip_with_all_emus: true  do
      get "/organizations/#{@org.display_login}/settings/copilot/custom_models"

      assert_response :not_found
    end
  end

  context "#new" do
    test "renders if the flag is enabled and the org has Copilot access" do
      Orca::Pipeline.stubs(:latest_completed_pipeline).returns(nil)
      Orca::Pipeline.stubs(:latest_pipeline).returns(nil)
      Orca::Client.any_instance.stubs(:get_rate_limit).returns(@under_rate_limit)
      as @admin
      get "/organizations/#{@org.display_login}/settings/copilot/custom_model/new"

      assert_response :ok

      assert_react_payload_equal("createPath", settings_org_copilot_custom_models_create_path(@org))
    end

    test "404s if feature flag is not set" do
      disable_feature_flag(:copilot_custom_models, @admin)

      as @admin
      get "/organizations/#{@org.display_login}/settings/copilot/custom_model/new"

      assert_response :not_found
    end

    # EMU factory for organizations has access to Copilot (`organization.has_copilot_for_business?` returns `true`)
    # so can be skipped
    test "404s if org does not have access to Copilot", skip_with_all_emus: true do
      org_without_copilot = create(:organization)
      enable_feature_flag(:copilot_dotcom_chat, org_without_copilot)
      admin = org_without_copilot.admins.first
      enable_feature_flag(:copilot_custom_models, admin)

      as admin
      get "/organizations/#{org_without_copilot.display_login}/settings/copilot/custom_model/new"

      assert_response :not_found
    end

    # EMUs need to be logged in for an EMU test to test anything EMU specific, so we can skip it
    test "404s if not logged in", skip_with_all_emus: true do
      get "/organizations/#{@org.display_login}/settings/copilot/custom_model/new"

      assert_response :not_found
    end

    test "checks for enough data to do a training" do
      Orca::Pipeline.stubs(:latest_completed_pipeline).returns(nil)
      Orca::Pipeline.stubs(:latest_pipeline).returns(nil)
      Orca::Client.any_instance.stubs(:get_rate_limit).returns(@under_rate_limit)
      as @admin
      get "/organizations/#{@org.display_login}/settings/copilot/custom_model/new"

      assert_react_payload_equal("enoughDataToTrain", true)
    end

    test "alerts page when not enough data to do a training" do
      Orca::Pipeline.stubs(:latest_completed_pipeline).returns(nil)
      Orca::Pipeline.stubs(:latest_pipeline).returns(nil)
      Orca::Client.any_instance.stubs(:get_rate_limit).returns(@under_rate_limit)
      org = create(:copilot_for_business_enabled_organization, admin: @admin)
      as @admin
      get "/organizations/#{org.display_login}/settings/copilot/custom_model/new"

      assert_react_payload_equal("enoughDataToTrain", false)
    end
  end

  context "#create" do
    test "returns errors if the request access repos not owned by the org" do
      Orca::Pipeline.stubs(:latest_completed_pipeline).returns(nil)
      Orca::Pipeline.stubs(:latest_pipeline).returns(nil)
      Orca::Client.any_instance.stubs(:get_rate_limit).returns(@under_rate_limit)
      as @admin
      repo = create(:repository)
      params = { repository_nwos: [repo.nwo] }
      post "/organizations/#{@org.display_login}/settings/copilot/custom_model/new", format: :json, params: params
      payload = JSON.parse(response.body)

      assert_equal payload["errors"].keys.sort, %w[repository_nwos]
      assert_equal response.status, 422
    end

    test "creates a valid entry and queues the pipeline run" do
      Orca::Pipeline.stubs(:latest_completed_pipeline).returns(nil)
      Orca::Pipeline.stubs(:latest_pipeline).returns(nil)
      Orca::Client.any_instance.stubs(:get_rate_limit).returns(@under_rate_limit)
      Orca::PipelineFormValidator.any_instance.stubs(:enqueue_pipeline).returns([true, @pipeline_id])

      as @admin

      params = {
        repository_nwos: @repositories.map(&:nwo),
        languages: @languages,
      }
      post "/organizations/#{@org.display_login}/settings/copilot/custom_model/new",
        format: :json,
        params: params

      body = JSON.parse(response.body)
      payload = body["payload"]
      assert_equal 200, response.status
      assert_equal "Successfully created training request", payload["message"]
      assert_equal settings_org_copilot_custom_model_trainings_show_path(@org, @pipeline_id),
        payload["redirect_url"]
    end

    test "request for all repositories and file languages" do
      Orca::Pipeline.stubs(:latest_completed_pipeline).returns(nil)
      Orca::Pipeline.stubs(:latest_pipeline).returns(nil)
      Orca::Client.any_instance.stubs(:get_rate_limit).returns(@under_rate_limit)
      Orca::PipelineFormValidator.any_instance.stubs(:enqueue_pipeline).returns([true, @pipeline_id])

      as @admin

      params = {
        repository_nwos: [],
        languages: []
      }

      post "/organizations/#{@org.display_login}/settings/copilot/custom_model/new",
        format: :json,
        params: params

      body = JSON.parse(response.body)
      payload = body["payload"]

      assert_equal response.status, 200
      assert_equal payload["message"], "Successfully created training request"
    end

    test "sets redirect_url to new pipeline" do
      Orca::Pipeline.stubs(:latest_completed_pipeline).returns(@org_pipeline)
      Orca::Pipeline.stubs(:latest_pipeline).returns(nil)
      Orca::Client.any_instance.stubs(:get_rate_limit).returns(@under_rate_limit)
      pipeline_id = SecureRandom.uuid
      Orca::PipelineFormValidator.any_instance.stubs(:enqueue_pipeline).returns([true, pipeline_id])

      as @admin

      params = {
        languages: [],
        repository_nwos: [],
      }

      post("/organizations/#{@org.display_login}/settings/copilot/custom_model/new", format: :json, params: params)

      body = JSON.parse(response.body)
      payload = body["payload"]

      assert_equal response.status, 200
      assert_equal payload["message"], "Successfully created training request"
      assert_equal settings_org_copilot_custom_model_trainings_show_path(
        @org, pipeline_id
      ), payload["redirect_url"]
    end

    test "returns an error if the orca server is not responsive" do
      Orca::Pipeline.stubs(:latest_completed_pipeline).returns(nil)
      Orca::Pipeline.stubs(:latest_pipeline).returns(nil)
      Orca::PipelineFormValidator.any_instance.stubs(:enqueue_pipeline).returns([false, nil])
      Orca::Client.any_instance.stubs(:get_rate_limit).returns(@under_rate_limit)
      as @admin
      params = {
        repository_nwos: @repositories.map(&:nwo),
        languages: @languages,
      }

      post "/organizations/#{@org.display_login}/settings/copilot/custom_model/new", format: :json, params: params
      assert_equal response.status, 500
    end
  end

  context "#edit" do
    test "renders if the flag is enabled and the org has Copilot access" do
      Orca::Pipeline.stubs(:fetch_by_id).returns(@org_pipeline)
      Orca::Client.any_instance.stubs(:get_rate_limit).returns(@under_rate_limit)
      as @admin
      get "/organizations/#{@org.display_login}/settings/copilot/custom_model/#{@pipeline_id}/edit"
      assert_response :ok
      assert_react_payload_equal("repoCount", 1)
      assert_react_payload_equal("languages", @languages)
    end

    test "404s if feature flag is not set" do
      disable_feature_flag(:copilot_custom_models, @admin)

      as @admin

      get "/organizations/#{@org.display_login}/settings/copilot/custom_model/#{@pipeline_id}/edit"

      assert_response :not_found
    end

    # EMU factory for organizations has access to Copilot (`organization.has_copilot_for_business?` returns `true`)
    # so can be skipped
    test "404s if org does not have access to Copilot", skip_with_all_emus: true do
      org_without_copilot = create(:organization)
      admin = org_without_copilot.admins.first
      enable_feature_flag(:copilot_custom_models, admin)

      as admin
      get "/organizations/#{org_without_copilot.display_login}/settings/copilot/custom_model/#{@pipeline_id}/edit"

      assert_response :not_found
    end

    # EMUs need to be logged in for an EMU test to test anything EMU specific, so we can skip it
    test "404s if not logged in", skip_with_all_emus: true do
      get "/organizations/#{@org.display_login}/settings/copilot/custom_model/#{@pipeline_id}/edit"

      assert_response :not_found
    end
  end

  context "#destroy" do
    test "returns correct redirect_url if successful and completed/training pipelines not present" do
      Orca::Pipeline.stubs(:fetch_by_id).returns(@org_pipeline)
      Orca::Pipeline.stubs(:delete_pipeline).returns("result")
      Orca::Pipeline.stubs(:latest_completed_pipeline).returns(nil)
      Orca::Pipeline.stubs(:latest_pipeline).returns(nil)

      as @admin
      delete "/organizations/#{@org.display_login}/settings/copilot/custom_model/#{@pipeline_id}"

      assert_response :ok
      payload = JSON.parse(response.body)["payload"]
      redirect_url = settings_org_copilot_custom_models_path(@org)
      assert_equal payload["redirect_url"], redirect_url
    end

    test "returns correct redirect_url if successful and completed/training pipelines present" do
      Orca::Pipeline.stubs(:fetch_by_id).returns(@org_pipeline)
      Orca::Pipeline.stubs(:delete_pipeline).returns("result")
      Orca::Pipeline.stubs(:latest_completed_pipeline).returns(nil)

      as @admin
      delete "/organizations/#{@org.display_login}/settings/copilot/custom_model/#{@org_pipeline.pipeline_id}"

      assert_response :ok
      payload = JSON.parse(response.body)["payload"]
      redirect_url = settings_org_copilot_custom_models_path(@org)
      assert_equal payload["redirect_url"], redirect_url
    end

    test "500s if Orca::Client::ServerError raised" do
      Orca::Pipeline.stubs(:fetch_by_id).returns(@org_pipeline)
      Orca::Pipeline.stubs(:delete_pipeline).raises(Orca::Client::ServerError)

      as @admin
      delete "/organizations/#{@org.display_login}/settings/copilot/custom_model/#{@pipeline_id}"

      assert_response :internal_server_error
    end

    test "404s if feature flag is not set" do
      disable_feature_flag(:copilot_custom_models, @admin)

      as @admin

      delete "/organizations/#{@org.display_login}/settings/copilot/custom_model/#{@pipeline_id}"

      assert_response :not_found
    end

    test "404s if org does not have access to Copilot", skip_with_all_emus: true do
      org_without_copilot = create(:organization)
      admin = org_without_copilot.admins.first
      enable_feature_flag(:copilot_custom_models, admin)

      as admin
      delete "/organizations/#{org_without_copilot.display_login}/settings/copilot/custom_model/#{@pipeline_id}"

      assert_response :not_found
    end

    test "404s if not logged in", skip_with_all_emus: true do
      delete "/organizations/#{@org.display_login}/settings/copilot/custom_model/#{@pipeline_id}"

      assert_response :not_found
    end
  end

  context "rate limiting" do
    test "rate limit the create page" do
      Orca::Client.any_instance.stubs(:get_rate_limit).returns(@rate_limited)
      Orca::Pipeline.stubs(:latest_completed_pipeline).returns(@org_pipeline)
      as @admin
      get "/organizations/#{@org.display_login}/settings/copilot/custom_model/new"

      assert_response :redirect
      assert_redirected_to settings_org_copilot_custom_models_path(@org)
    end

    test "rate limit the edit page" do
      Orca::Pipeline.stubs(:fetch_by_id).returns(@org_pipeline)
      Orca::Client.any_instance.stubs(:get_rate_limit).returns(@rate_limited)
      Orca::Pipeline.stubs(:latest_completed_pipeline).returns(@org_pipeline)
      as @admin
      get "/organizations/#{@org.display_login}/settings/copilot/custom_model/#{@pipeline_id}/edit"

      assert_response :redirect
      assert_redirected_to settings_org_copilot_custom_models_path(@org)
    end

    test "the show page outputs the rate limit state" do
      Orca::Pipeline.stubs(:fetch_by_id).returns(@org_pipeline)
      Orca::Pipeline.stubs(:latest_pipeline).returns(@org_pipeline)
      Orca::Pipeline.stubs(:latest_completed_pipeline).returns(@org_pipeline)

      Orca::Client.any_instance.stubs(:get_rate_limit).returns(@rate_limited)
      as @admin
      get "/organizations/#{@org.display_login}/settings/copilot/custom_model/training/#{@pipeline_id}"

      assert_response :ok
      assert_react_payload_equal("withinRateLimit", false)
    end
  end

end unless GitHub.enterprise?
