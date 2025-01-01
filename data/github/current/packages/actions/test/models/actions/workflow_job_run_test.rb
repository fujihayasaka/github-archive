# typed: true
# frozen_string_literal: true
require "test_helper"
require "test_helpers/launch/identity_helper"
require "monolith-twirp-actionsresults-core"

class Actions::WorkflowJobRunTest < GitHub::TestCase
  include Launch::IdentityHelper

  fixtures do
    make_trusted_oauth_apps_owner

    @repository = create :repository
    @owner = @repository.owner

    @actions_summary_url = "https://github.test/summary_url?jobId=#{SecureRandom.uuid}&$expand=SignedContent"
    @signed_url = "https://github.test/signed_summary_url"
    @legacy_summary_payload = {
      "truncated" => false,
      "stepSummaries" => [
        {
          "stepRecordId" => SecureRandom.uuid,
          "contentBase64" => Base64.encode64(Faker::Movies::StarWars.quote),
          "truncated" => false,
          "createdOn" => DateTime.now.iso8601,
        }
      ]
    }

    @results_summary_payload = MonolithTwirp::ActionsResults::Core::V1::GetJobSummaryResponse.new(
      workflow_job_run_backend_id: SecureRandom.uuid,
      is_truncated: true,
      step_summaries: [
        MonolithTwirp::ActionsResults::Core::V1::GetJobSummaryResponse::StepSummary.new(
          content: "🐷 oink".b,
          created_at: Google::Protobuf::Timestamp.new(seconds: DateTime.now.to_i),
          is_truncated: true
        ),
        MonolithTwirp::ActionsResults::Core::V1::GetJobSummaryResponse::StepSummary.new(
          content: Faker::Movies::StarWars.quote.b,
          created_at: Google::Protobuf::Timestamp.new(seconds: DateTime.now.to_i),
          is_truncated: false
        ),
      ]
    ).freeze
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  def mock_launch_get_summary_exchange_url(workflow_job_run, lab: false)
    repository = workflow_job_run.repository
    unauthenticated_url = "https://github.test/summary_url?jobId=#{workflow_job_run.check_run.external_id}&$expand=SignedContent"
    resp = GitHub::Launch::Services::Checks::SummaryExchangeURLResponse.new(
      authenticated_url: @signed_url,
      expires_at: Google::Protobuf::Timestamp.new(seconds: (DateTime.now + 1.hour).to_i),
    )

    client_klass = lab ? Launch::Twirp::ChecksLabClient : Launch::Twirp::ChecksClient
    client = client_klass.new
    Launch::Twirp.expects(:checks_client).with(lab:).returns(client)

    client.expects(:rpc)
      .with(
        :GetSummaryExchangeURL,
        unauthenticated_job_summaries_url: unauthenticated_url,
        repository_id: launch_identity(repository),
      )
      .returns(TwirpResponse.new(value: resp, status: 200, call_succeeded: true)).once
  end

  test "basic ActiveRecord relationships" do
    check_suite = create(:check_suite_for_actions_app, repository: @repository)
    check_run = create(:check_run, :success, check_suite: check_suite)

    workflow_job_run = check_run.workflow_job_run

    assert_equal @repository, workflow_job_run.repository
    assert_equal check_run, workflow_job_run.check_run
    assert_equal check_suite.workflow_run, workflow_job_run.workflow_run
    assert_equal check_suite.workflow_run.latest_workflow_run_execution, workflow_job_run.workflow_run_execution
  end

  context "#get_blocking_resources" do
    test "returns empty array if concurrency value is nil" do
      check_suite = create(:check_suite_for_actions_app, repository: @repository)
      check_run = create(:check_run_for_actions_app, :success, :with_legacy_summary, check_suite: check_suite)
      workflow_job_run = check_run.workflow_job_run

      workflow_job_run.concurrency = nil

      assert_equal [], workflow_job_run.get_blocking_resources
    end

    test "returns empty array if no blocking resources" do
      check_suite = create(:check_suite_for_actions_app, repository: @repository)
      check_run = create(:check_run_for_actions_app, :success, :with_legacy_summary, check_suite: check_suite)
      workflow_job_run = check_run.workflow_job_run

      workflow_job_run.concurrency = "{}"

      assert_equal [], workflow_job_run.get_blocking_resources
    end

    test "returns empty array if no check suite or check run ids are set" do
      check_suite = create(:check_suite_for_actions_app, repository: @repository)
      check_run = create(:check_run_for_actions_app, :success, :with_legacy_summary, check_suite: check_suite)
      workflow_job_run = check_run.workflow_job_run

      workflow_job_run.concurrency = "{\"group\":\"staging\",\"waiting_on_resource\":{\"identifier\":\"staging\",\"check_run_id\":null,\"check_suite_id\":null}}"

      assert_equal [], workflow_job_run.get_blocking_resources
    end
  end

  context "#get_summary" do
    test "successfully returns summary given a legacy url" do
      faraday_stub = GitHub::FaradayClient::Internal.new do |f|
        f.adapter :test do |stub|
          stub.get @signed_url do
            [200, {}, @legacy_summary_payload.to_json]
          end
        end
      end

      Actions::WorkflowJobRun
        .any_instance
        .expects(:actions_service_client)
        .returns(faraday_stub)

      check_suite = create(:check_suite_for_actions_app, repository: @repository)
      check_run = create(:check_run_for_actions_app, :success, :with_legacy_summary, check_suite: check_suite)
      workflow_job_run = check_run.workflow_job_run

      mock_launch_get_summary_exchange_url(workflow_job_run)

      assert_legacy_summary_payload workflow_job_run.get_summary
    end

    test "successfully returns summary given a legacy url for Launch lab" do
      faraday_stub = GitHub::FaradayClient::Internal.new do |f|
        f.adapter :test do |stub|
          stub.get @signed_url do
            [200, {}, @legacy_summary_payload.to_json]
          end
        end
      end

      Actions::WorkflowJobRun
        .any_instance
        .expects(:actions_service_client)
        .returns(faraday_stub)

      launch_lab_app = GitHub.launch_lab_github_app || create(:launch_lab_integration)
      GitHub.stubs(:launch_lab_github_app).returns(launch_lab_app)
      lab_check_suite = create(
        :check_suite_for_actions_app,
        github_app: launch_lab_app,
        repository: @repository,
        workflow_file_path: ".github/workflows-lab/test.yml"
      )
      check_run = create(:check_run_for_actions_app, :success, :with_legacy_summary, check_suite: lab_check_suite)
      workflow_job_run = check_run.workflow_job_run

      mock_launch_get_summary_exchange_url(workflow_job_run, lab: true)

      assert_legacy_summary_payload workflow_job_run.get_summary
    end

    test "successfully returns summary given a results service url" do
      check_suite = create(:check_suite_for_actions_app, repository: @repository)
      check_run = create(:check_run_for_actions_app, :success, :with_results_summary, check_suite: check_suite)
      workflow_job_run = check_run.workflow_job_run

      ActionsResults::Twirp::JobSummaryClient
        .any_instance
        .expects(:get_job_summary)
        .with(equals({
          workflow_run_backend_id: check_suite.external_id,
          workflow_job_run_backend_id: check_run.external_id
        }))
        .returns(TwirpResponse.new(
          status: 200,
          call_succeeded: true,
          value: @results_summary_payload
        ))

      assert_results_summary_payload workflow_job_run.get_summary
    end

    test "returns nil if summary url does not exist" do
      Actions::WorkflowJobRun
        .any_instance
        .expects(:get_summary_from_actions_service)
        .never

      check_suite = create(:check_suite_for_actions_app, repository: @repository)
      check_run = create(:check_run_for_actions_app, :success, check_suite: check_suite)
      workflow_job_run = check_run.workflow_job_run

      job_summary = workflow_job_run.get_summary

      assert_nil job_summary
    end

    test "returns nil if actions request fails" do
      faraday_stub = GitHub::FaradayClient::Internal.new do |f|
        f.adapter :test do |stub|
          stub.get @signed_url do
            [500, {}, "💥"]
          end
        end
      end

      Actions::WorkflowJobRun
        .any_instance
        .expects(:actions_service_client)
        .returns(faraday_stub)

      check_suite = create(:check_suite_for_actions_app, repository: @repository)
      check_run = create(:check_run_for_actions_app, :success, :with_legacy_summary, check_suite: check_suite)
      workflow_job_run = check_run.workflow_job_run

      mock_launch_get_summary_exchange_url(workflow_job_run)

      assert_nil workflow_job_run.get_summary
    end

    test "falls back to actions service if results service returns an error" do
      faraday_stub = GitHub::FaradayClient::Internal.new do |f|
        f.adapter :test do |stub|
          stub.get @signed_url do
            [200, {}, @legacy_summary_payload.to_json]
          end
        end
      end

      Actions::WorkflowJobRun
        .any_instance
        .expects(:actions_service_client)
        .returns(faraday_stub)

      check_suite = create(:check_suite_for_actions_app, repository: @repository)
      check_run = create(:check_run_for_actions_app, :success, :with_results_summary, check_suite: check_suite)
      workflow_job_run = check_run.workflow_job_run

      mock_launch_get_summary_exchange_url(workflow_job_run)

      ActionsResults::Twirp::JobSummaryClient
        .any_instance
        .expects(:get_job_summary)
        .returns(TwirpResponse.new(
          status: 500,
          call_succeeded: false,
        ))

      refute_nil workflow_job_run.get_summary
    end

    test "returns nil if bad json response from actions service" do
      faraday_stub = GitHub::FaradayClient::Internal.new do |f|
        f.adapter :test do |stub|
          stub.get @signed_url do
            [200, {}, "!!!'not' a :valid: json!!!"]
          end
        end
      end

      Actions::WorkflowJobRun
        .any_instance
        .expects(:actions_service_client)
        .returns(faraday_stub)

      check_suite = create(:check_suite_for_actions_app, repository: @repository)
      check_run = create(:check_run_for_actions_app, :success, :with_legacy_summary, check_suite: check_suite)
      workflow_job_run = check_run.workflow_job_run

      mock_launch_get_summary_exchange_url(workflow_job_run)

      job_summary = workflow_job_run.get_summary

      assert_nil job_summary
    end
  end

  private

  def assert_legacy_summary_payload(job_summary)
    assert job_summary.is_a? Actions::JobSummary

    expected_payload = @legacy_summary_payload

    assert_equal expected_payload["truncated"], job_summary.truncated, "job_summary.truncated mismatch"

    expected_payload["stepSummaries"].each_with_index do |expected_step_payload, index|
      step_summary = job_summary.step_summaries[index]

      assert_equal expected_step_payload["stepRecordId"], step_summary[:step_record_id], "step_summary[#{index}][:step_record_id], mismatch"
      assert_equal expected_step_payload["contentBase64"], ::Base64.encode64(step_summary[:content]), "step_summary[#{index}][:content], mismatch"
      assert_equal expected_step_payload["createdOn"], step_summary[:created_on].iso8601, "step_summary[#{index}][:created_on], mismatch"
    end
  end

  def assert_results_summary_payload(job_summary)
    assert job_summary.is_a? Actions::JobSummary

    expected_payload = @results_summary_payload

    assert_equal expected_payload.is_truncated, job_summary.truncated, "job_summary.truncated"

    expected_payload.step_summaries.each_with_index do |expected_step_payload, index|
      step_summary = job_summary.step_summaries[index]

      assert_equal expected_step_payload.content, step_summary[:content], "step_summary[#{index}][:content], mismatch"
      assert_equal expected_step_payload.is_truncated, step_summary[:truncated], "step_summary[#{index}][:truncated], mismatch"
      assert_equal expected_step_payload.created_at.to_time, step_summary[:created_on], "step_summary[#{index}][:created_on], mismatch"
    end
  end
end
