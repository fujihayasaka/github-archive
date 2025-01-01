# typed: true
# frozen_string_literal: true

require "test_helper"

class ActionsRepositoryUsageTest < GitHub::TestCase
  fixtures do
    @repository = create(:repository)
  end

  test "it sets repository usage for a day" do
    now = Time.now
    Actions::RepositoryUsage.set_usage_for(@repository.id, time: now, count: 100)

    assert_equal 100, Actions::RepositoryUsage.usage_for(@repository.id, time: now)
  end

  test "it increments repository usage for a day without prior data" do
    now = Time.now
    Actions::RepositoryUsage.increment_usage_for(@repository.id, time: now, count: 100)

    assert_equal 100, Actions::RepositoryUsage.usage_for(@repository.id, time: now)
  end

  test "it increments repository usage for a day with prior data" do
    now = Time.now
    Actions::RepositoryUsage.set_usage_for(@repository.id, time: now, count: 50)
    Actions::RepositoryUsage.increment_usage_for(@repository.id, time: now, count: 50)

    assert_equal 100, Actions::RepositoryUsage.usage_for(@repository.id, time: now)
  end

  test "it returns 0 for a repository without any usage" do
    assert_equal 0, Actions::RepositoryUsage.usage_for(@repository.id, time: Time.now)
    assert_equal 0, Actions::RepositoryUsage.uses_in_the_past_week(@repository.id)
  end

  test "it aggregates usage for a week - set" do
    now = Time.now
    (1..10).each_entry do |lookback|
      Actions::RepositoryUsage.set_usage_for(@repository.id, time: now - lookback.days, count: 10)
    end

    assert_equal 70, Actions::RepositoryUsage.uses_in_the_past_week(@repository.id)
  end

  test "it aggregates usage for a week - increment" do
    now = Time.now
    increment_total = 0
    (1..10).each_entry do |lookback|
      Actions::RepositoryUsage.increment_usage_for(@repository.id, time: now - lookback.days, count: 10)
    end

    assert_equal 70, Actions::RepositoryUsage.uses_in_the_past_week(@repository.id)
  end

  test "it returns 0 uses for a week for a repository without any usage" do
    assert_equal 0, Actions::RepositoryUsage.uses_in_the_past_week(@repository.id)
  end
end
