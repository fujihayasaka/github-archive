# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestCodeownersTest < GitHub::TestCase
  fixtures do
    @owner = create :user, login: "owner", plan: "large"
    @collab = create :user, login: "collab"
    org = create :organization, login: "acme", admin: create(:user), plan: "business", seats: 10
    @team = create(:team, organization: org, name: "Employee", privacy: :closed)

    @repo = create :repository, owner: org, from_example: :rebase_pull_request
    @repo.add_member @collab
    @repo.add_member @owner
    @team.add_member @collab
    @team.add_repository(@repo, :push)

    @pull = create :pull_request,
      repository:       @repo,
      base_repository:  @repo,
      base_user:        @repo.owner,
      base_ref:         "master",
      head_repository:  @repo,
      head_user:        @repo.owner,
      head_ref:         "contrib",
      issue:            create(:issue, repository: @repo, user: @owner),
      draft:            false
  end

  setup do
    reset_repo_root
    example_repo :rebase_pull_request, @repo
  end

  def commit_codeowners_file(contents, ref: "master")
    @repo.refs.find(ref).append_commit({ message: "Add CODEOWNERS file", committer: @owner }, @owner) do |files|
      files.add("CODEOWNERS", contents)
    end
  end

  test "returns the correct owners based on the PR diff" do
    commit_codeowners_file(<<~CODEOWNERS)
      *       foo@example.com @owner

      README  @collab
      *.js    @collab-2
    CODEOWNERS

    assert_same_elements [@owner, @collab], @pull.codeowners.to_a
    refute @pull.codeowners_paths_load_error?
  end

  test "returns team owners" do
    commit_codeowners_file(<<~CODEOWNERS)
      *       foo@example.com @owner

      README  @#{@team}
      *.js    @collab-2
    CODEOWNERS

    assert_same_elements [@owner, @team], @pull.codeowners.to_a
  end

  test "works even if the PR head ref is deleted" do
    commit_codeowners_file(<<~CODEOWNERS)
      *       foo@example.com @owner

      README  @collab
      *.js    @collab-2
    CODEOWNERS

    @repo.refs.find(@pull.head_ref).delete(@owner)

    assert_same_elements [@owner, @collab], @pull.reload.codeowners.to_a
  end

  test "returns no owners if using the Chromium format" do
    commit_codeowners_file(<<~CODEOWNERS)
      owner@example.com

      per-file *.js=js@example.com
    CODEOWNERS

    assert_equal [], @pull.reload.codeowners.to_a
  end

  test "returns no owners if the CODEOWNERS file is not parsable" do
    commit_codeowners_file(<<~CODEOWNERS)
      This file is not formatted. It's just random words.
    CODEOWNERS

    assert_equal [], @pull.reload.codeowners.to_a
  end

  test "sets a flag if there is an error in loading diff when initializing the codeowners object" do
    commit_codeowners_file(<<~CODEOWNERS)
      *       foo@example.com @owner

      README  @collab
      *.js    @collab-2
    CODEOWNERS

    @pull.historical_comparison.init_diffs.stubs(:deltas).raises(GitRPC::ObjectMissing)
    # stub for asynchronous version
    GitHub::Diff.any_instance.stubs(:deltas).raises(GitRPC::ObjectMissing)

    assert_predicate @pull.codeowners, :none?
    assert @pull.codeowners_paths_load_error?
  end

  test "raises an error when using the bang version if there is an error in loading diff when initializing the codeowners object" do
    commit_codeowners_file(<<~CODEOWNERS)
      *       foo@example.com @owner

      README  @collab
      *.js    @collab-2
    CODEOWNERS

    GitHub::Diff.any_instance.stubs(:deltas).raises(GitRPC::ObjectMissing)

    assert_predicate @pull.codeowners, :none?

    error = assert_raises PullRequest::DetermineCodeownersError do
      @pull.codeowners!
    end

    assert GitRPC::ObjectMissing, error.class
  end

  test "returns an empty array if has trouble loading diff paths" do
    commit_codeowners_file(<<~CODEOWNERS)
      *       foo@example.com @owner

      README  @collab
      *.js    @collab-2
    CODEOWNERS

    @pull.historical_comparison.init_diffs.stubs(:deltas).raises(GitRPC::ObjectMissing)
    # stub for asynchronous version
    GitHub::Diff.any_instance.stubs(:deltas).raises(GitRPC::ObjectMissing)
    assert_same_elements [], @pull.codeowners.to_a
  end

  test "doesn't bother computing diff paths if no CODEOWNERS file" do
    @pull.expects(:historical_comparison).never
    assert_same_elements [], @pull.codeowners.to_a
  end
end
