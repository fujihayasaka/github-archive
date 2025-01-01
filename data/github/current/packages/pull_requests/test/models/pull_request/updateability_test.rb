# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestUpdateabilityTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "ari")
    @source = create(:repository, owner: @owner, from_example: :pull_request_source)

    @forker = create(:user, login: "bwalsh")
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)

    @other_forker = create(:user, login: "dhh")
    @other_fork = create(:fork_repository, forker: @other_forker, fork_repo: @source, from_example: :pull_request_fork)

    @issue = create(:issue, user: @forker, repository: @source)
    @pull = PullRequest.create_for(@source, {
      base:  "master",
      head:  "#{@fork.user}:topic",
      user:  @issue.user,
      issue: @issue,
    })
  end

  setup do
    reset_repo_root
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork
    example_repo :pull_request_fork,   @other_fork

    @pull.create_merge_commit

    reset_cache
  end

  def commit_to_repo(repo, branch: "master", filename: "README.txt", content: nil)
    metadata = { message: "commit", committer: repo.owner }

    ref = repo.heads.find(branch)
    ref.append_commit(metadata, repo.owner) do |files|
      files.add(filename, content || "test content at #{Time.now.to_f}")
    end

    refute_nil ref.target_oid
    ref.target_oid
  end

  context "#check_mergeability" do
    test "checks if the user has write permissions to the head branch" do
      assert_predicate @pull.updateability.check_mergeability(@forker), :success?
      refute_predicate @pull.updateability.check_mergeability(@owner), :success?
      refute_predicate @pull.updateability.check_mergeability(@other_forker), :success?

      @pull.fork_collab_allowed!

      assert_predicate @pull.updateability.check_mergeability(@forker), :success?
      assert_predicate @pull.updateability.check_mergeability(@owner), :success?
      refute_predicate @pull.updateability.check_mergeability(@other_forker), :success?
    end

    test "checks if there is a merge conflict between head and base" do
      assert_predicate @pull.updateability.check_mergeability(@forker), :success?

      perform_enqueued_jobs(only: [CreatePullRequestMergeCommitJob]) do
        commit_to_repo(@source, branch: "master", filename: "new_file.txt", content: "Some change")
        commit_to_repo(@fork, branch: "topic", filename: "new_file.txt", content: "Some conflicting change")
        @pull.enqueue_mergeable_update
      end
      @pull.reload

      refute_predicate @pull.updateability.check_mergeability(@forker), :success?

      perform_enqueued_jobs(only: [CreatePullRequestMergeCommitJob]) do
        commit_to_repo(@source, branch: "master", filename: "new_file.txt", content: "Some unifying change")
        commit_to_repo(@fork, branch: "topic", filename: "new_file.txt", content: "Some unifying change")
        @pull.enqueue_mergeable_update
      end
      @pull.reload

      assert_predicate @pull.updateability.check_mergeability(@forker), :success?
    end

    test "checks if the head branch is protected with required linear history" do
      @pull.head_repository.protect_branch(@pull.head_ref_name, creator: @forker, required_linear_history: true, entry_point: :test_case)
      refute_predicate @pull.updateability.check_required_linear_history, :success?
    end
  end
end
