# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../orca_test_helpers"

class OrcaPipelineTest < GitHub::TestCase
  include OrcaTestHelpers

  fixtures do
    @admin = create(:user)
    @organization = create(:organization, admin: @admin)
    @repositories = create_list(:repository, 2, owner: @organization)
    @pipeline_id = SecureRandom.uuid

    @created_at = 1.hour.ago.freeze
    @started_at = 30.minutes.ago.freeze
    @completed_at = 10.minutes.ago.freeze
  end

  sig { returns(GitHub::Orca::PipelineDetails) }
  def build_pipeline_details
    language_filters = %w[Python Javascript].map do |lang|
      language = Linguist::Language.find_by_name(lang)
      GitHub::Orca::LingustLanguage.new(
        name: language.name,
        language_id: language.language_id,
      )
    end
    GitHub::Orca::PipelineDetails.new(
      pipeline: GitHub::Orca::Pipeline.new(
        id: @pipeline_id,
        organization: GitHub::Orca::Organization.new(
          login: @organization.login,
          id: @organization.id,
          analytics_tracking_id: @organization.analytics_tracking_id,
        ),
        status: GitHub::Orca::PipelineStatus::PIPELINE_STATUS_COMPLETED,
        status_string: "PIPELINE_STATUS_COMPLETED",
        created_at: @created_at.iso8601,
        started_at: @started_at.iso8601,
        completed_at: @completed_at.iso8601,
        training_inputs: GitHub::Orca::PipelineTrainingInputs.new(
          language_filters: language_filters,
          repositories: @repositories.map do |repository|
            GitHub::Orca::Repository.new(
              id: repository.id,
              name: repository.name,
              clone_url: repository.clone_url,
            )
          end,
          use_private_telemetry: false,
        ),
        request_actor: GitHub::Orca::Actor.new(
          login: @admin.display_login,
          id: @admin.id,
          analytics_tracking_id: @admin.analytics_tracking_id,
        ),
        request_source: Orca::Pipeline::REQUEST_SOURCE_DOTCOM,
      )
    )
  end

  context "#pipeline_id" do
    test "returns the pipeline ID" do
      pipeline = Orca::Pipeline.new(build_pipeline_details)
      assert_equal @pipeline_id, pipeline.pipeline_id
    end
  end

  context "#organization" do
    test "returns the organization from the database" do
      pipeline = Orca::Pipeline.new(build_pipeline_details)
      assert_equal @organization, pipeline.organization
    end

    test "memoizes the organization" do
      pipeline = Orca::Pipeline.new(build_pipeline_details)
      assert_same pipeline.organization, pipeline.organization
    end
  end

  context "#repositories" do
    test "returns the repositories from the database" do
      pipeline = Orca::Pipeline.new(build_pipeline_details)
      assert_equal @repositories.sort, pipeline.repositories.sort
    end

    test "memoizes the repositories" do
      pipeline = Orca::Pipeline.new(build_pipeline_details)
      assert_same pipeline.repositories.first, pipeline.repositories.first
    end

    test "ignores repositories that have been deleted" do
      pipeline = Orca::Pipeline.new(build_pipeline_details)
      @repositories.first.destroy
      assert_equal 1, pipeline.repositories.count
    end
  end

  context "#repository_count" do
    test "returns the number of non-deleted repos" do
      pipeline = Orca::Pipeline.new(build_pipeline_details)
      @repositories.first.destroy
      assert_equal 1, pipeline.repository_count
    end

    test "memoizes the result" do
      pipeline = Orca::Pipeline.new(build_pipeline_details)
      assert_equal 2, pipeline.repository_count
      @repositories.first.destroy
      assert_equal 2, pipeline.repository_count
    end
  end

  context "#languages" do
    test "returns the languages" do
      pipeline = Orca::Pipeline.new(build_pipeline_details)
      assert_equal %w[JavaScript Python], pipeline.languages
    end
  end

  context "#actor" do
    test "returns the actor from the orca" do
      pipeline = Orca::Pipeline.new(build_pipeline_details)
      assert_equal @admin.display_login, T.must(pipeline.actor).login
      assert_equal @admin.id, T.must(pipeline.actor).id
    end

  end

  context "#as_json" do
    test "returns the pipeline as a JSON object" do
      pipeline = Orca::Pipeline.new(build_pipeline_details)
      next_show_path = "/next/path"
      Rails.application.routes.url_helpers.stubs(:settings_org_copilot_custom_model_trainings_show_path).returns(next_show_path)

      expected = {
        id: @pipeline_id,
        languages: [
          {
           name: "Python",
           color: "#3572A5",
           id: 303
          },
          {
            name: "JavaScript",
            color: "#f1e05a",
            id: 183
          }
        ],
        repositories: @repositories.map do |repo|
          {
            id: T.must(repo.id),
            name: T.must(repo.name)
          }
        end,
        status: "PIPELINE_STATUS_COMPLETED",
        createdAt: @created_at.iso8601,
        actorLogin: @admin.display_login,
      }
      json_p = pipeline.as_json
      assert_equal expected[:id], json_p[:id]
      assert_equal expected[:languages].sort_by { |r| r[:id] }, json_p[:languages].sort_by { |r| r[:id] }
      assert_equal 2, json_p[:repositoryCount]
      assert_equal expected[:status], json_p[:status]
      assert_equal expected[:createdAt], json_p[:createdAt]
      assert_equal expected[:actorLogin], json_p[:actorLogin]
    end
  end

  context "#private_telemetry_collected?" do
    test "returns true when training input use_private_telemetry true" do
      pipeline_details = build_pipeline_details
      training_inputs = T.must(T.must(pipeline_details.pipeline).training_inputs)
      training_inputs.use_private_telemetry = true
      T.must(pipeline_details.pipeline).training_inputs = training_inputs

      pipeline = Orca::Pipeline.new(pipeline_details)
      assert pipeline.private_telemetry_collected?
    end

    test "returns false when training input use_private_telemetry false" do
      pipeline_details = build_pipeline_details
      training_inputs = T.must(T.must(pipeline_details.pipeline).training_inputs)
      training_inputs.use_private_telemetry = false
      T.must(pipeline_details.pipeline).training_inputs = training_inputs

      pipeline = Orca::Pipeline.new(pipeline_details)
      refute pipeline.private_telemetry_collected?
    end
  end

  test "get pipelines" do
    stub_orca_request "GetPipelines",
      GitHub::Orca::GetPipelinesRequest.new(
        organization: Orca::Client.organization(@organization),
      ),
      GitHub::Orca::GetPipelinesResponse.new(
          pipelines: [GitHub::Orca::Pipeline.new(
            id: "1223",
            organization: Orca::Client.organization(@organization),
            completed_at: Time.now.to_s,
          )]
      )
    pipelines = Orca::Pipeline.get_pipelines(
      @organization
    )
    refute_nil pipelines
    pipeline = pipelines.first
    assert_equal T.must(pipeline).pipeline_id, "1223"
  end
end
