# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryRepoIsSearchableTest < GitHub::TestCase
  fixtures do
    @defunkt = create(:user, login: "defunkt", plan: "medium")
    @repo = create(:repository, name: "cool_repo", owner: @defunkt)
  end

  test "is searchable with owner" do
    assert_equal @repo.owner, @defunkt
    assert_predicate @repo, :repo_is_searchable?
  end

  test "is not searchable with nil owner" do
    # this is required to trick validation + Trilogy null checks for :owner in Repository
    @repo.owner = nil
    assert_nil @repo.owner
    refute_predicate @repo, :repo_is_searchable?
  end
end
