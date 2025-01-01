# typed: true
# frozen_string_literal: true

require "test_helper"

class CodeScanningDependencyTest < GitHub::TestCase
  fixtures do
    @user = create :user
    @repo = create(:repository)
    make_trusted_oauth_apps_owner
    @code_scanning_app = create(:code_scanning_integration)
  end

  test "in progress with very long key" do
    @repo.store_code_scanning_action_in_progress("refs/heads/bar", "c" * 9999, "cat1", "123")
  end

  test "create_code_scanning_check_suite fills in the branch name into a newly created check suite" do
    code_scanning_check_suite = CheckRun.create_code_scanning_check_suite(
      repository: @repo,
      annotated_commit_oid: "deadbeef",
      analyzed_commit_oid: "deadbeef",
      ref: "refs/heads/the-branch-name",
      base_ref: "refs/heads/main",
      base_sha: "deadbeef",
      )

    assert_equal("the-branch-name", code_scanning_check_suite.check_suite.head_branch)
  end

  test "checkruns are deleted when their tool is not present" do
    @actions_app = create(:launch_integration)
    @owner = create(:paid_user)
    @org = create(:organization, admin: @owner)
    repo = create(:private_repository, owner: @org)
    @installation = make_integration_installation(integration: @actions_app, repository: repo, permissions: { "security_events" => :write })
    dogstats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(dogstats)

    args = {
      repository: repo,
      annotated_commit_oid: "def",
      analyzed_commit_oid: "def",
      ref: "abc",
    }

    check_runs = CheckRun.create_for_code_scanning_analysis(
      tool_names: %w[Foo bar],
      base_ref: "baz",
      base_sha: "qux",
      **args
    )
    assert_equal 2, dogstats.increments("code_scanning.check_run.created").length

    check_run_foo = check_runs.find { |c| c.code_scanning_tool_name == "Foo" }
    check_run_bar = check_runs.find { |c| c.code_scanning_tool_name == "bar" }
    refute_nil check_run_bar
    refute_nil check_run_foo

    ret = CheckRun.align_checkruns_with_tools(
      check_run_ids: check_runs.map(&:id),
      tools: [{ name: "foo", tool_id: 0 }],
      **args,
    )

    assert_equal [check_run_foo], ret
    assert_equal 1, dogstats.increments("code_scanning.check_run.deleted").length

    assert_equal "Foo", CheckRun.find(check_run_foo.id).name
    assert_raises ActiveRecord::RecordNotFound do
      CheckRun.find(check_run_bar.id)
    end
  end

  test "checkruns are not aligned if the run already exists with the canonical name" do
    @actions_app = create(:launch_integration)
    @owner = create(:paid_user)
    @org = create(:organization, admin: @owner)
    repo = create(:private_repository, owner: @org)
    @installation = make_integration_installation(integration: @actions_app, repository: repo, permissions: { "security_events" => :write })

    args = {
      repository: repo,
      annotated_commit_oid: "def",
      analyzed_commit_oid: "def",
      ref: "abc",
    }

    check_runs = CheckRun.create_for_code_scanning_analysis(
      tool_names: ["Golang security checks by gosec"],
      base_ref: "baz",
      base_sha: "qux",
      **args
    )

    assert_equal "gosec", check_runs.first.name

    CheckRun.expects(:create_for_code_scanning_analysis).never

    ret = CheckRun.align_checkruns_with_tools(
      check_run_ids: check_runs.map(&:id),
      tools: [{ name: "Golang security checks by gosec", tool_id: 0 }],
      **args,
    )

    assert_equal 1, ret.length
  end
end
