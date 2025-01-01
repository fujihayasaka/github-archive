# typed: true
# frozen_string_literal: true

require "test_helper"
require "json"

class RepositoryNetworkGraphTest < GitHub::TestCase
  fixtures do
    @owner   = create(:user)
    @forker1 = create(:user)
    @forker2 = create(:user)

    @source = create(:repository, name: "ng", owner: @owner, from_example: :network_graph_source)
    @fork1 = create(:fork_repository, forker: @forker1, fork_repo: @source, from_example: :network_graph_fork)
    @fork2 = create(:fork_repository, forker: @forker2, fork_repo: @source, from_example: :network_graph_another_fork)

    @now = Time.now.freeze

    @source.update_attribute :pushed_at, @now + 1

    @fork1.update_attribute :pushed_at, @now + 2

    @fork2.update_attribute :pushed_at, @now + 3
  end

  test "initializing a network graph" do
    ng = Repository::NetworkGraph.for_repository(@source)

    assert_nil ng.network_hash
    refute_nil ng.current_network_hash
    refute ng.current?
    refute ng.running?
    assert_enqueued_jobs 0, only: RepositoryNetworkGraphBuilderJob, queue: :netgraph
  end

  test "enqueueing a network graph in the background job" do
    ng = Repository::NetworkGraph.for_repository(@source)

    assert_enqueued_jobs 1, only: RepositoryNetworkGraphBuilderJob, queue: :netgraph do
      ng.build
    end

    ng = Repository::NetworkGraph.find(ng.id)
    assert ng.running?
    refute ng.current?
  end

  test "building a network graph in the background job" do
    ng = Repository::NetworkGraph.for_repository(@source)

    perform_enqueued_jobs(only: [RepositoryNetworkGraphBuilderJob]) do
      ng.build
    end

    ng = Repository::NetworkGraph.find(ng.id)

    assert ng.current?
    refute ng.running?
  end

  test "building an ordered list of network repos" do
    ng = Repository::NetworkGraph.for_repository(@source)
    ng.build!

    assert ng.current?
    refute ng.running?
    expected = [@source, @fork2, @fork1].map { |r| r.owner.login }
    meta = JSON.parse(ng.meta_json)
    assert_equal expected, meta["users"].map { |u| u["name"] }
  end

  test "limits the number of network repos" do
    GitHub.stubs(:network_graph_fork_limit).returns(1)

    ng = Repository::NetworkGraph.for_repository(@source)
    ng.build!

    assert ng.current?
    refute ng.running?
    expected = [@source, @fork2].map { |r| r.owner.login }
    meta = JSON.parse(ng.meta_json)
    assert_equal expected, meta["users"].map { |u| u["name"] }
  end

  test "generates a different network hash when the network changes" do
    ng1 = Repository::NetworkGraph.for_repository(@source)
    original_hash = ng1.current_network_hash
    fork_repo = create(:fork_repository, forker: create(:user), fork_repo: @source)
    fork_repo.update(pushed_at: @now + 5.minutes)

    ng2 = Repository::NetworkGraph.for_repository(@source)
    refute_equal original_hash, ng2.current_network_hash
  end

  test "building network meta users" do
    ng = Repository::NetworkGraph.for_repository(@source)
    ng.build!

    assert ng.current?
    refute ng.running?
    meta = JSON.parse(ng.meta_json)

    assert_equal [
      {
        "repo"  => "ng",
        "name"  => @owner.login,
        "heads" => [{ "name" => "master", "id" => "8abd54838e6ecf23cdb60fd1110f3772a878c76c" }],
      },
      {
        "repo"  => "ng",
        "name"  => @forker2.login,
        "heads" => [{ "name" => "master",    "id" => "7a63e9bd749c88b2763faa07478830fda1800f3b" },
                    { "name" => "another",   "id" => "3e4b407ac5604e79d3de38c9fdc28676100b18a7" },
                    { "name" => "topic",     "id" => "948a3b08cbce11ee0df1687b04defacadd11fce3" }],
      },
      {
        "repo"  => "ng",
        "name"  => @forker1.login,
        "heads" => [{ "name" => "master",    "id" => "7a63e9bd749c88b2763faa07478830fda1800f3b" },
                    { "name" => "wontapply", "id" => "a84a2aff0f5c51a606db6390e584e40a9dba0129" },
                    { "name" => "topic",     "id" => "948a3b08cbce11ee0df1687b04defacadd11fce3" }],
      },
    ], meta["users"]
  end

  test "limits number of branches" do
    GitHub.stubs(:network_graph_branch_limit).returns(2)
    ng = Repository::NetworkGraph.for_repository(@source)
    ng.build!

    assert ng.current?
    refute ng.running?
    meta = JSON.parse(ng.meta_json)

    assert_equal [
      {
        "repo"  => "ng",
        "name"  => @owner.login,
        "heads" => [{ "name" => "master", "id" => "8abd54838e6ecf23cdb60fd1110f3772a878c76c" }],
      },
      {
        "repo"  => "ng",
        "name"  => @forker2.login,
        "heads" => [{ "name" => "master",    "id" => "7a63e9bd749c88b2763faa07478830fda1800f3b" },
                    { "name" => "another",   "id" => "3e4b407ac5604e79d3de38c9fdc28676100b18a7" }],
      },
      {
        "repo"  => "ng",
        "name"  => @forker1.login,
        "heads" => [{ "name" => "master",    "id" => "7a63e9bd749c88b2763faa07478830fda1800f3b" },
                    { "name" => "wontapply", "id" => "a84a2aff0f5c51a606db6390e584e40a9dba0129" }],
      },
    ], meta["users"]
  end

  if GitHub.spamminess_check_enabled?
    test "excludes spammy users" do
      perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
        @forker1.mark_as_spammy
      end
      assert @forker1.spammy?

      ng = Repository::NetworkGraph.for_repository(@source)
      ng.build!

      assert ng.current?
      refute ng.running?
      expected = [@source, @fork2].map { |r| r.owner.login }
      meta = JSON.parse(ng.meta_json)

      assert_equal expected, meta["users"].map { |u| u["name"] }
      assert_equal [
        {
          "repo"  => "ng",
          "name"  => @owner.login,
          "heads" => [{ "name" => "master", "id" => "8abd54838e6ecf23cdb60fd1110f3772a878c76c" }],
        },
        {
          "repo"  => "ng",
          "name"  => @forker2.login,
          "heads" => [{ "name" => "master",    "id" => "7a63e9bd749c88b2763faa07478830fda1800f3b" },
                      { "name" => "another",   "id" => "3e4b407ac5604e79d3de38c9fdc28676100b18a7" },
                      { "name" => "topic",     "id" => "948a3b08cbce11ee0df1687b04defacadd11fce3" }],
        },
      ], meta["users"]
    end
  end

  test "building network meta dates" do
    ng = Repository::NetworkGraph.for_repository(@source)
    ng.build!
    assert ng.current?
    refute ng.running?

    meta = JSON.parse(ng.meta_json)
    assert_equal %w[
      2010-04-28 2010-04-28 2010-04-28 2010-04-28 2010-04-28
      2010-04-28 2010-04-28 2010-04-28 2010-04-28 2010-04-28
      2010-04-28 2010-04-30 2019-05-07
    ], meta["dates"]
  end

  test "building network meta blocks" do
    ng = Repository::NetworkGraph.for_repository(@source)
    ng.build!
    assert ng.current?
    refute ng.running?

    meta = JSON.parse(ng.meta_json)
    assert_equal [
      { "name" => @owner.login,   "count" => 1, "start" => 0 },
      { "name" => @forker2.login, "count" => 3, "start" => 1 },
      { "name" => @forker1.login, "count" => 1, "start" => 4 },
    ], meta["blocks"]
  end

  test "building network meta focus" do
    ng = Repository::NetworkGraph.for_repository(@source)
    ng.build!
    assert ng.current?
    refute ng.running?

    meta = JSON.parse(ng.meta_json)
    assert_equal 6, meta["focus"]
  end

  test "building network meta nethash" do
    ng = Repository::NetworkGraph.for_repository(@source)
    ng.build!
    assert ng.current?
    refute ng.running?

    meta = JSON.parse(ng.meta_json)
    assert_equal ng.current_network_hash, meta["nethash"]
  end

  test "building network data json" do
    ng = Repository::NetworkGraph.for_repository(@source)
    ng.build!
    assert ng.current?
    refute ng.running?

    data = JSON.parse(ng.data_json(nil, nil))
    assert_equal 13, data["commits"].length
  end

  test "#running sets the job status' ttl if it is unspecified" do
    job_status = JobStatus.create
    assert_equal JobStatus::DEFAULT_OVERALL_TTL, job_status.ttl

    ng = Repository::NetworkGraph.for_repository(@source)
    ng.job_status_id = job_status.id

    assert_predicate ng, :running?

    job_status = JobStatus.find!(job_status.id)
    assert_equal Repository::NetworkGraph::JOB_STATUS_TTL, job_status.ttl
  end

  test "creates a JobStatus and returns its ID to track job status" do
    ng = Repository::NetworkGraph.for_repository(@source)
    assert_nil ng.job_status_id

    ng.build
    assert job_status_id = ng.job_status_id

    job_status = JobStatus.find(job_status_id)
    assert job_status, "expected a job status to be created"

    assert_equal Repository::NetworkGraph::JOB_STATUS_TTL, job_status.ttl
  end
end
