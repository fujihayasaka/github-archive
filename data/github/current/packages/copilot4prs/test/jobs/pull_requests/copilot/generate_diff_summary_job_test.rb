# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class PullRequests::Copilot::GenerateDiffSummaryJobTest < GitHub::TestCase
  include JobTestHelper
  include PushTestHelper

  fixtures do
    @repository = create :repository, from_example: :pull_request_source
    @pull_request = create :pull_request, :with_mergeable_head, repository: @repository
    @actor = @pull_request.user
  end

  setup do
    PullRequests::Copilot.stubs(:copilot_for_prs_enabled?).returns(true)
    @subject = PullRequests::Copilot::GenerateDiffSummaryJob
    @frozen_now = Time.now.utc
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions(
      job: @subject,
      args: [job_status_id: make_job_status.id]
    )
  end

  test "it retries on dirty exit" do
    assert_retry_on_dirty_exit(
      job: @subject,
      args: [job_status_id: make_job_status.id]
    )
  end

  context ".enqueue" do
    test "creates a job status and schedules the job" do
      @subject.expects(:perform_later).
        with do |args|
          status = Copilot::CompletionJobStatus.find(args[:job_status_id])

          assert_equal @repository.id, status.context[:repository_id]
          assert_equal @actor.id, status.context[:actor_id]
          assert_equal @pull_request.base_sha, status.context[:base_revision]
          assert_equal @pull_request.head_sha, status.context[:head_revision]
        end

      @subject.enqueue(repository: @repository, actor: @actor, base_revision: @pull_request.base_sha, head_revision: @pull_request.head_sha, head_repo_id: @pull_request.head_repository_id, token: "a_secret_token")
    end
  end

  context "#perform" do
    test "stores the completion in the job status context" do
      stub_pipeline_perform "Hello world!"

      job_status = make_job_status
      @subject.perform_now(job_status_id: job_status.id)

      job_status = reload(job_status)
      assert_equal "Hello world!", job_status.context[:completion]
    end

    test "keeps track of the job status state" do
      stub_pipeline_perform "Hello world!"
      Copilot::CompletionJobStatus.any_instance.expects(:started!)

      job_status = make_job_status
      @subject.perform_now(job_status_id: job_status.id)

      job_status = reload(job_status)
      assert_predicate job_status, :success?
    end

    test "records resoved commit OIDs" do
      stub_pipeline_perform "Hello world!"

      job_status = make_job_status
      @subject.perform_now(job_status_id: job_status.id)

      job_status = reload(job_status)
      assert_equal @pull_request.base_sha, job_status.context[:base_oid]
      assert_equal @pull_request.head_sha, job_status.context[:head_oid]
    end

    test "records timings" do
      stub_pipeline_perform "Hello world!"

      job_status = make_job_status
      @subject.perform_now(job_status_id: job_status.id)

      job_status = reload(job_status)
      refute_nil job_status.context[:job_timing_ms]
      refute_nil job_status.context[:overall_timing_ms]
    end

    test "errors out the job status if something goes wrong" do
      PullRequests::Copilot::Prompt::SummaryPipeline.any_instance.expects(:perform).raises(StandardError, "boom")

      job_status = make_job_status
      assert_raises do
        @subject.perform_now(job_status_id: job_status.id)
      end

      job_status = reload(job_status)
      assert_predicate job_status, :error?
      assert_includes job_status.error_message, "Something went wrong"
    end

    test "sets job status to error if diffsfilter returns an empty array" do
      PullRequests::Copilot::DiffsFilter.any_instance.expects(:to_a).returns([])

      job_status = make_job_status
      @subject.perform_now(job_status_id: job_status.id)

      job_status = reload(job_status)
      assert_predicate job_status, :error?
      assert_includes job_status.error_message, "This pull request contains files that could not be processed. Please contact our support team for more details."
    end

    test "raises an UnauthorizedComparisonError when viewer lacks access to head repository" do
      random_head_repo = create(:private_repository, from_example: :simple)
      push_changes(repository: random_head_repo, changes: {
        path: "README.md",
        content: "My favorite ice cream flavor is vanilla" },
      )
      refute random_head_repo.readable_by?(@actor), "need a repo the actor does not have access to"

      job_status = Copilot::CompletionJobStatus.create(context: {
        repository_id: @repository.id,
        actor_id: @actor.id,
        base_revision: GitHub::NULL_OID,
        head_revision: random_head_repo.ref_to_sha(random_head_repo.default_branch),
        head_repo_id: random_head_repo.id,
      })

      Copilot::User::CopilotApi.any_instance.expects(:async_create_chat_completion).never

      error = assert_raises(PullRequests::Copilot::GenerateDiffSummaryJob::UnauthorizedComparisonError) do
        @subject.perform_now(job_status_id: job_status.id)
      end

      assert_equal "#{@actor} does not have permission for the requested comparison", error.message
      job_status = reload(job_status)
      refute_predicate job_status, :success?
      assert_equal "#{@actor} does not have permission for the requested comparison", job_status.error_message
    end

    test "raises an UnauthorizedComparisonError when viewer lacks access to base repository" do
      @repository.update!(private: true)
      refute @repository.readable_by?(@actor), "need a repo the actor does not have access to"
      job_status = make_job_status

      Copilot::User::CopilotApi.any_instance.expects(:async_create_chat_completion).never

      error = assert_raises(PullRequests::Copilot::GenerateDiffSummaryJob::UnauthorizedComparisonError) do
        @subject.perform_now(job_status_id: job_status.id)
      end

      assert_equal "#{@actor} does not have permission for the requested comparison", error.message
      job_status = reload(job_status)
      refute_predicate job_status, :success?
      assert_equal "#{@actor} does not have permission for the requested comparison", job_status.error_message
    end

    test "raises an RAIError if RAI response is returned from CAPI" do
      CopilotAPI.async_connection.expects(:send)
        .returns(ConcurrentFaraday::FutureResponse.new.fulfill(Faraday::Response.new(status: 403, response_headers: { "X-Ratelimit-User-Retry-After": "0" }, body: "content_filtered in response")))

      job_status = make_job_status
      assert_raises(CopilotAPI::RAIError) do
        @subject.perform_now(job_status_id: job_status.id)
      end

      job_status = reload(job_status)
      assert_predicate job_status, :error?
      assert_includes job_status.error_message, "The response was filtered due to the content of the request. Please contact our support team."
    end

    test "raises an EmptyResponseError if empty response is returned from CAPI" do
      CopilotAPI.async_connection.expects(:send)
        .returns(ConcurrentFaraday::FutureResponse.new.fulfill(Faraday::Response.new(status: 200, response_headers: { "X-Ratelimit-User-Retry-After": "0" }, body: "")))

      job_status = make_job_status
      assert_raises(PullRequests::Copilot::Prompt::SummaryPipeline::EmptyResponseError) do
        @subject.perform_now(job_status_id: job_status.id)
      end

      job_status = reload(job_status)
      assert_predicate job_status, :error?
      assert_includes job_status.error_message, "Something went wrong"
    end

    test "pushes info to Failbot context" do
      stub_pipeline_perform "Hello world!"
      Failbot.context.clear

      job_status = make_job_status
      @subject.perform_now(job_status_id: job_status.id)

      failbot_context = Failbot.squash_contexts(Failbot.context)

      assert_equal @repository.id, failbot_context["gh.repo.id"]
      assert_equal @actor.id, failbot_context["gh.actor.id"]
    end

    test "doesn't mark the job status as errored if retryable error is thrown" do
      PullRequests::Copilot::Prompt::SummaryPipeline.any_instance.expects(:perform).raises(ActiveRecord::ConnectionFailed)

      job_status = make_job_status
      @subject.perform_now(job_status_id: job_status.id)

      job_status = reload(job_status)
      assert_predicate job_status, :started?
    end
  end

  context "#metrics" do
    test "tracks overall job timing and status" do
      stub_copilot_api_calls
      Timecop.freeze @frozen_now do
        GitHub.dogstats.expects(:timing_since).at_least_once
        GitHub.dogstats.expects(:timing_since).with("copilot.prompt.generate_diff_summary_job", @frozen_now, tags: ["status:success"])
        job_status = make_job_status
        @subject.perform_now(job_status_id: job_status.id)
      end
    end

    test "tracks overall job timing and status if there is an error" do
      Timecop.freeze @frozen_now do
        PullRequests::Copilot::Prompt::SummaryPipeline.any_instance.
          expects(:perform).raises(StandardError, "boom")

        GitHub.dogstats.expects(:timing_since).with("copilot.prompt.generate_diff_summary_job", @frozen_now, tags: ["status:error", "error:StandardError"])
        job_status = make_job_status
        assert_raises do
          @subject.perform_now(job_status_id: job_status.id)
        end
      end
    end

    test "tracks overall job timing and status if there is an expected error" do
      Timecop.freeze @frozen_now do
        GitHub.dogstats.expects(:timing_since).at_least_once
        GitHub.dogstats.expects(:timing_since).with("copilot.prompt.generate_diff_summary_job", @frozen_now, tags: ["status:error", "error:CopilotAPI::RAIError"])
        CopilotAPI.async_connection.expects(:send)
          .returns(ConcurrentFaraday::FutureResponse.new.fulfill(Faraday::Response.new(status: 403, response_headers: { "X-Ratelimit-User-Retry-After": "0" }, body: "content_filtered in response")))

        job_status = make_job_status
        assert_raises(CopilotAPI::RAIError) do
          @subject.perform_now(job_status_id: job_status.id)
        end
      end
    end
  end


  def make_job_status
    Copilot::CompletionJobStatus.create(
      context: {
        repository_id: @repository.id,
        actor_id: @actor.id,
        base_revision: @pull_request.base_sha,
        head_revision: @pull_request.head_sha,
        head_repo_id: @pull_request.head_repository_id
      }
    )
  end

  def reload(job_status)
    job_status.class.find(job_status.id)
  end

  def stub_pipeline_perform(text)
    PullRequests::Copilot::Prompt::SummaryPipeline.any_instance.expects(:perform).returns(text)
  end

  def stub_copilot_api_calls
    Copilot::User::CopilotApi.any_instance.stubs(:async_create_chat_completion)
      .returns(Promise.new.fulfill({ "choices" => [{ "message" => { "content" => "* F8318c86R1: Adds a new method called `hello_world`." } }] }))
      .then.returns(Promise.new.fulfill({ "choices" => [{ "message" => { "content" => "Adds a new `hello_world` method." } }] }))
      .then.returns(Promise.new.fulfill({ "choices" => [{ "message" => { "content" => "Updates the project to add a new hello world style method." } }] }))
  end
end unless GitHub.enterprise?
