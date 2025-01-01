# typed: true
# frozen_string_literal: true

require "test_helper"

class AchievementRepositoryListTest < GitHub::TestCase
  fixtures do
    @repos = create_list(:repository, 3)
  end

  context "#filter" do
    test "filters out repositories that do not pass a predicate" do
      original = AchievementRepositoryList.new(repositories: @repos)
      filtered = original.filter { |repository| repository != @repos.first }
      assert_equal [@repos.second, @repos.third], filtered.repositories
    end
  end

  context "#filter_promise" do
    test "passes an empty collection through as-is" do
      original = AchievementRepositoryList.none
      filtered_promise = original.filter_promise do |_repository|
        fail "Should not be called"
      end
      filtered = filtered_promise.sync
      assert_empty filtered.repositories
    end

    test "filters out repositories that don't pass the filter" do
      original = AchievementRepositoryList.new(repositories: @repos)
      filtered_promise = original.filter_promise do |repository|
        Promise.resolve(repository != @repos.second)
      end
      filtered = filtered_promise.sync
      assert_equal [@repos.first, @repos.third], filtered.repositories
    end
  end
end
