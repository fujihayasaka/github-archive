# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryCloneJobTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, from_example: :simple)

    @blank_repo = create(:repository)
    @blank_repo.rpc.remove

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "runs job" do
    RepositoryCloneJob.perform_now(@repo, @blank_repo)
    @blank_repo.reload

    assert_predicate @blank_repo, :exists_on_disk?
    refute_predicate @blank_repo, :empty?
    assert_equal @blank_repo.refs.find("master").target_oid, @repo.refs.find("master").target_oid
  end

  test "runs job when source_repo is nil" do
    RepositoryCloneJob.perform_now(nil, @blank_repo)
    @blank_repo.reload

    refute_predicate @blank_repo, :exists_on_disk?
    assert_predicate @blank_repo, :empty?
  end
end
