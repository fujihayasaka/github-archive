# typed: true
# frozen_string_literal: true

require "test_helpers/notifications/test_helper"

class NotificationsTest < GitHub::TestCase
  fixtures do
    @repository = create(:repository)
    @user = @repository.owner
    GitHub.newsies.unsubscribe @user, @repository
  end

  setup do
    # get this as close to Time.now as possible
    GitHub.newsies.subscribe_to_list(@user, @repository)
  end

  test "list subscribers" do
    assert_equal [@user], GitHub.newsies.subscribers(@repository).value
  end

  test "list subscription status" do
    status = GitHub.newsies.subscription_status(@user, @repository).value
    assert status.valid?, "status is not valid"
    assert status.subscribed?, "status is not subscribed"
    assert !status.ignored?, "status is ignored"
    assert_utc_time status.created_at
  end

  test "user subscriptions" do
    subscriptions = GitHub.newsies.subscriptions(@user).value
    assert_equal 1, subscriptions.size
    assert_equal Newsies::List.to_object(@repository), subscriptions[0].list
    assert_utc_time subscriptions[0].created_at
  end

  def assert_utc_time(time, expected = nil)
    expected = (expected || Time.now).utc
    assert_kind_of Time, time, "not a time"
    assert time.utc?, "not in utc"
    assert_in_delta expected.to_f, time.to_f, 3.0, "doesn't match Time.now: #{time.inspect} != #{expected.inspect}"
  end
end
