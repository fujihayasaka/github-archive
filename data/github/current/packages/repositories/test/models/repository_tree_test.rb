# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryTreeTest < GitHub::TestCase
  fixtures do
    @root = create(:repository)
    @fork_one = create(:fork_repository, forker: create(:user), fork_repo: @root)
    @fork_two = create(:fork_repository, forker: create(:user), fork_repo: @fork_one)
  end

  context "#parents" do
    test "returns all parents" do
      assert_equal [], @root.parents
      assert_equal [@root], @fork_one.parents
      assert_equal [@fork_one, @root], @fork_two.parents
    end

    test "raises if parents count exceed hierarchy maximum" do
      Repository::NetworkDependency.stub_const(:MAX_HIERARCHY_DEPTH, 1) do
        assert_raises { @fork_two.parents }
      end
    end
  end

  context "#descendants" do
    test "returns all descendants" do
      assert_same_elements [@fork_one, @fork_two], @root.descendants
      assert_same_elements [@fork_two], @fork_one.descendants
      assert_same_elements [], @fork_two.descendants
    end
  end
end
