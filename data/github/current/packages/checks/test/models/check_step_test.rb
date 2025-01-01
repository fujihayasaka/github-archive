# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-actionsresults-core"
require "test_helpers/launch/exchange_url_helper"

class CheckStepTest < GitHub::TestCase
  include StringFromBinaryTestHelper
  include Launch::ArtifactExchangeUrlHelper

  fixtures do
    @workflow_run_backend_id = "eaabb1cc-1e70-4c57-8307-fb1207223ec3"
    @workflow_job_run_backend_id = "a5317d85-aec2-4e03-a018-e723e2713cf5"
    @workflow_step_backend_id = "22047b8f-5e15-48ba-93af-d7e0b4fc779e"
    @completed_log_url_from_results = "results://actions-results/run/#{@workflow_run_backend_id}/job/#{@workflow_job_run_backend_id}/step/#{@workflow_step_backend_id}?actions_url=https://logs.github.com/some-unique-slug-step1"
    @authenticated_url = "https://logs.github.com/some-unique-slug-step1?token=1234"

    @results_log_url_payload = MonolithTwirp::ActionsResults::Core::V1::GetCompletedStepLogResponse.new(
      log_url: @completed_log_url_from_results
    ).freeze
  end

  context "#get_signed_completed_log_url" do
    test "successfully returns a signed completed step URL when a results URL is present" do
      check_step = build(:check_step, :results_completed_log_url)

      ActionsResults::Twirp::LogClient
        .any_instance
        .expects(:get_completed_step_log_url)
        .with(equals({
          workflow_run_backend_id: @workflow_run_backend_id,
          workflow_job_run_backend_id: @workflow_job_run_backend_id,
          step_backend_id: @workflow_step_backend_id,
        }))
        .returns(TwirpResponse.new(
          status: 200,
          call_succeeded: true,
          value: @results_log_url_payload
        ))

      assert_equal @completed_log_url_from_results, check_step.get_signed_completed_log_url
    end

    test "successfully returns a signed completed step URL when no results URL is present" do
      check_step = build(:check_step, :completed)
      check_suite = check_step.check_run.check_suite

      ActionsResults::Twirp::LogClient
      .any_instance
      .expects(:get_completed_step_log_url)
      .never

      mock_completed_step_log_exchange_url(
        authenticated_url: @authenticated_url,
        repository: check_suite.repository,
      )

      assert_equal check_step.get_signed_completed_log_url, @authenticated_url
    end

    test "returns nil if a completed step URL does not exist" do
      check_step = build(:check_step)

      assert_nil check_step.get_signed_completed_log_url
    end

    test "returns nil if request to Actions Service fails" do
      check_step = build(:check_step, :completed)
      check_suite = check_step.check_run.check_suite

      ActionsResults::Twirp::LogClient
      .any_instance
      .expects(:get_completed_step_log_url)
      .never

      mock_completed_step_log_exchange_url(
        authenticated_url: @authenticated_url,
        repository: check_suite.repository,
        response_status: 500,
      )

      assert_nil check_step.get_signed_completed_log_url
    end

    test "falls back to Actions Service if the request to the Results Service raises an error" do
      check_step = build(:check_step, :results_completed_log_url)
      check_suite = check_step.check_run.check_suite

      ActionsResults::Twirp::LogClient
      .any_instance
      .expects(:get_completed_step_log_url)
      .returns(TwirpResponse.new(
        status: 500,
        call_succeeded: false,
      ))

      mock_completed_step_log_exchange_url(
        authenticated_url: @authenticated_url,
        repository: check_suite.repository,
      )

      refute_nil check_step.get_signed_completed_log_url
    end

    test "falls back to Actions Service if the request to the Results Service returns an empty URL" do
      check_step = build(:check_step, :results_completed_log_url)
      check_suite = check_step.check_run.check_suite
      blank_url = MonolithTwirp::ActionsResults::Core::V1::GetCompletedStepLogResponse.new(
        log_url: ""
      ).freeze

      ActionsResults::Twirp::LogClient
      .any_instance
      .expects(:get_completed_step_log_url)
      .returns(TwirpResponse.new(
        status: 200,
        call_succeeded: true,
        value: blank_url
      ))

      mock_completed_step_log_exchange_url(
        authenticated_url: @authenticated_url,
        repository: check_suite.repository,
      )

      refute_nil check_step.get_signed_completed_log_url
    end

  end

  test "copies `repository_id` from the `check_run`" do
    check_run = create :check_run
    check_step = create :check_step, check_run: check_run

    refute_nil check_step.repository_id
    assert_equal check_run.repository_id, check_step.repository_id
  end

  context "#seconds_to_completion" do
    test "returns seconds difference between completed_at and started_at" do
      start_time = Time.parse("2019-05-15T16:00:00Z")
      completion_time = start_time + 1.minute + 10.seconds
      check_step = build(:check_step, started_at: start_time, completed_at: completion_time)

      assert_equal 70, check_step.seconds_to_completion
    end

    test "returns 0 when completed_at and started_at are the same" do
      start_time = Time.parse("2019-05-15T16:00:00Z")
      completion_time = start_time
      check_step = build(:check_step, started_at: start_time, completed_at: completion_time)

      assert_equal 0, check_step.seconds_to_completion
    end

    test "returns nil when completed_at is earlier than started_at" do
      start_time = Time.parse("2019-05-15T16:00:00Z")
      completion_time = start_time - 1.second
      check_step = build(:check_step, started_at: start_time, completed_at: completion_time)

      assert_nil check_step.seconds_to_completion
    end

    test "returns nil when completed_at is nil" do
      start_time = Time.parse("2019-05-15T16:00:00Z")
      completion_time = nil
      check_step = build(:check_step, started_at: start_time, completed_at: completion_time)

      assert_nil check_step.seconds_to_completion
    end

    test "returns nil when started_at is nil" do
      start_time = nil
      completion_time = Time.parse("2019-05-15T16:00:00Z")
      check_step = build(:check_step, started_at: start_time, completed_at: completion_time)

      assert_nil check_step.seconds_to_completion
    end
  end

  context "#truncate_fields" do
    test "truncates varbinary fields" do
      check_step = create :check_step, name: "a" * 2000
      assert_equal CheckStep::MAX_VARBINARY_FIELD_LENGTH, check_step.name.bytesize
    end

    test "reports truncation stats to datadog" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      create :check_step, name: "a" * 2000

      assert_equal 1, GitHub.dogstats.increments("field_truncator", tags: ["class:CheckStep", "field:name"]).length
    end

    test "supports emoji for name" do
      check_step = create(:check_step, name: "we ❤️ emojis")

      assert_multibyte_tracked_changes(check_step, :name)
    end
  end

  context "#save" do
    test "scopes update queries to repository id when feature is enabled" do
      check_step = create(:check_step)

      check_step.number = 2

      _, queries = log_queries do
        check_step.save
      end

      refute queries.any? { |q| q.digested_sql.match?(/\AUPDATE check_steps SET (.*) WHERE check_steps.id = \?\Z/) }, "Expected no update query that wasn't scoped to a repo. Got:\n#{queries.map(&:digested_sql).select { |q| q.start_with?("UPDATE check_steps") }}"
      assert queries.any? { |q| q.digested_sql.match?(/\AUPDATE check_steps SET (.*) WHERE check_steps.id = \? AND check_steps.repository_id = \?\Z/) }, "Expected update query to be scoped to repo. Got:\n#{queries.map(&:digested_sql).select { |q| q.start_with?("UPDATE check_steps") }}"
    end
  end

  context "#from_results_step" do
    test "converts a results step to a check step" do
      step = create(:check_step, status: :completed, conclusion: :success, completed_at: Time.now.utc, completed_log_lines: 123)
      from_results = CheckStep.from_results_step(
        step: step.to_proto_object,
        repository_id: step.repository_id,
        check_run_id: step.check_run_id
      )

      ignored_db_attributes = %w[id created_at updated_at]
      assert_equal step.attributes.except(*ignored_db_attributes), from_results.attributes.except(*ignored_db_attributes)
    end

    test "uses nil timestamps for nil & zero values" do
      step = create(:check_step)
      step_proto = step.to_proto_object
      step_proto.started_at = Google::Protobuf::Timestamp.new(seconds: 0, nanos: 0)
      step_proto.completed_at = nil

      from_results = CheckStep.from_results_step(
        step: step_proto,
        repository_id: step.repository_id,
        check_run_id: step.check_run_id
      )

      assert_nil from_results.started_at
      assert_nil from_results.completed_at
    end
  end
end
