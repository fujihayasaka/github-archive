# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/pull_requests"

class RestoreHeadRefTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers

  fixtures do
    @pull = make_pr_and_repos
    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "is true when head ref is deleted" do
    @pull.head_repository.heads.find("topic").delete(@pull.user)
    assert @pull.async_head_ref_restorable_by?(@pull.user).sync
  end

  test "is false when the repo is locked for migration" do
    @pull.base_repository.lock_for_migration
    refute @pull.async_head_ref_restorable_by?(@pull.user).sync
  end

  test "is false when the head repo is missing" do
    @pull.head_repository.destroy
    @pull.reload
    refute @pull.async_head_ref_restorable_by?(@pull.user).sync
  end

  test "is false when user lacks push permission to head repo" do
    user = create(:user)
    @pull.repository.add_member(user)
    @pull.reload
    refute @pull.async_head_ref_restorable_by?(user).sync
  end
end
