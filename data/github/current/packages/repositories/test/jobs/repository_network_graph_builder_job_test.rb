# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RepositoryNetworkGraphBuilderJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @repo = create(:repository, from_example: :network_graph_source)
    @network_graph = @repo.network_graph
  end

  setup do
    @job_status = @network_graph.send(:create_job_status)
  end

  test "lock key is per network graph record" do
    job = RepositoryNetworkGraphBuilderJob.new(repository_network_graph_id: @network_graph.id)
    assert_equal @network_graph.id.to_s, job.lock_key
  end

  test "retries if the job status is not found" do
    @job_status.destroy

    RepositoryNetworkGraphBuilderJob.any_instance.expects(:retry_job)

    assert_nothing_raised do
      perform_enqueued_jobs(only: [RepositoryNetworkGraphBuilderJob]) do
        RepositoryNetworkGraphBuilderJob.perform_later(repository_network_graph_id: @network_graph.id)
      end
    end
  end

  test "keeps track of the job status" do
    assert_predicate @job_status, :pending?

    RepositoryNetworkGraphBuilderJob.perform_now(repository_network_graph_id: @network_graph.id)

    assert job_status = Repositories::JobStatus.find!(@network_graph.job_status_id_with_prefix)
    assert_predicate job_status, :success?
  end

  test "updates the job status if there is an exception" do
    assert_predicate @job_status, :pending?

    Repository::NetworkGraph.any_instance.stubs(:build!).raises(StandardError.new("BOOM!"))

    assert_raises StandardError do
      RepositoryNetworkGraphBuilderJob.perform_now(repository_network_graph_id: @network_graph.id)
    end

    assert job_status = Repositories::JobStatus.find!(@network_graph.job_status_id_with_prefix)
    assert_predicate job_status, :error?
  end

  test "supplies useful context for Failbot" do
    RepositoryNetworkGraphBuilderJob.perform_now(repository_network_graph_id: @network_graph.id)

    ctx = Failbot.squash_contexts(Failbot.context)
    assert_equal @repo.id, ctx["gh.repo.id"]
    assert_equal @network_graph.job_status_id_with_prefix, ctx["gh.job_status.id"]
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: RepositoryNetworkGraphBuilderJob, args: [repository_network_graph_id: @network_graph.id]
  end
end
