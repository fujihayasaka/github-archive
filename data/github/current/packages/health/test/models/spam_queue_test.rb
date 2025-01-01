# typed: true
# frozen_string_literal: true

require "test_helper"

class SpamQueueTest < GitHub::TestCase
  fixtures do
    @triage_worker = create :user, login: "triage-worker"
    @queue = create :spam_queue, name: "psq"
    @issue = create(:issue)
  end

  test "#human_name capitalizes each word" do
    q = SpamQueue.new name: "new_users"
    assert_equal "New Users", q.human_name
  end

  test "#name= normalizes input" do
    [
      "New User Triage",
      "new_user_triage",
      :new_user_triage,
    ].each do |user_entered_name|
      q = SpamQueue.new(name: user_entered_name)
      assert_equal "new_user_triage", q.name
    end
  end

  test "instruments creation" do
    events = subscribe "spam_queue.create"
    q = SpamQueue.create(name: "my_new_queue")

    expected_payload = {
      name: "my_new_queue",
      spam_queue_id: q.id,
    }

    assert event = events.pop, "expected an instrumentation event"
    assert_equal expected_payload, event.payload
  end

  test "instruments deletion" do
    events = subscribe "spam_queue.destroy"
    q = SpamQueue.create(name: "my_new_queue")
    q.destroy

    expected_payload = {
      name: "my_new_queue",
      spam_queue_id: q.id,
    }

    assert event = events.pop, "expected an instrumentation event"
    assert_equal expected_payload, event.payload
  end

  context "includes user?" do
    test "returns the user if in the queue" do
      foobar_user = create :user, login: "foobar"
      q = create :spam_queue, name: "user_triage"
      q.entries.create user: foobar_user, added_by: create(:user)

      sqe = q.includes_user?("foobar")
      refute_nil sqe
      assert_equal "foobar", sqe.user_login

      sqe = q.includes_user?(foobar_user)
      refute_nil sqe
      assert_equal "foobar", sqe.user_login
    end

    test "returns nil if the user isn't in the queue" do
      user = create :user, login: "foobar"
      q = create :spam_queue, name: "user_triage"
      assert_nil q.includes_user?("foobar")
      assert_nil q.includes_user?(user)
    end
  end

  context "#get_and_lock_entries" do
    test "returns unlocked entries" do
      triage_worker2 = create(:user)
      triage_worker3 = create(:user)
      entries = 6.times.map do |_n|
        user = create(:user)
        @queue.entries.create user: user,
          added_by: @triage_worker,
          spam_source: @issue,
          spam_queue: @queue,
          additional_context: "Foo Bar Baz"
      end

      assert_equal entries[0..1], @queue.get_and_lock_entries(user: @triage_worker)
      assert_equal entries[2..3], @queue.get_and_lock_entries(user: triage_worker2)
      assert_equal entries[4..5], @queue.get_and_lock_entries(user: triage_worker3)
    end

    test "returns entries locked by worker" do
      entries = 3.times.map do |_n|
        user = create(:user)
        @queue.entries.create user: user,
          added_by: @triage_worker,
          spam_source: @issue,
          spam_queue: @queue,
          additional_context: "Foo Bar Baz"
      end

      assert_equal entries[0..1], @queue.get_and_lock_entries(user: @triage_worker)
      assert_equal entries[0..1], @queue.get_and_lock_entries(user: @triage_worker)
    end

    test "returns entries locked by worker with id greater than previous_id" do
      entries = 4.times.map do |_n|
        user = create(:user)
        @queue.entries.create user: user,
          added_by: @triage_worker,
          spam_source: @issue,
          spam_queue: @queue,
          additional_context: "Foo Bar Baz"
      end

      assert_equal entries[0..1], @queue.get_and_lock_entries(user: @triage_worker)
      entries_again = @queue.get_and_lock_entries(user: @triage_worker)
      assert_equal entries[0..1], entries_again
      assert_equal entries[2..3], @queue.get_and_lock_entries(user: @triage_worker, previous_id: entries_again.map(&:id).max)
    end

    test "returns entries with stale lock" do
      triage_worker2 = create(:user)
      entries = 3.times.map do |_n|
        user = create(:user)
        @queue.entries.create user: user,
          added_by: @triage_worker,
          spam_source: @issue,
          spam_queue: @queue,
          additional_context: "Foo Bar Baz",
          locked_by: triage_worker2,
          locked_at: 3.minutes.ago
      end

      assert_equal entries[0..1], @queue.get_and_lock_entries(user: @triage_worker)
    end

    test "uses count argument" do
      entries = 4.times.map do |_n|
        user = create(:user)
        @queue.entries.create user: user,
          added_by: @triage_worker,
          spam_source: @issue,
          spam_queue: @queue,
          additional_context: "Foo Bar Baz"
      end

      assert_equal entries[0..2], @queue.get_and_lock_entries(count: 3, user: @triage_worker)
    end

    test "uses locked_at_minimum argument" do
      triage_worker2 = create(:user)
      entries = 3.times.map do |_n|
        user = create(:user)
        @queue.entries.create user: user,
          added_by: @triage_worker,
          spam_source: @issue,
          spam_queue: @queue,
          additional_context: "Foo Bar Baz",
          locked_by: triage_worker2,
          locked_at: 2.seconds.ago
      end

      assert_equal entries[0..1], @queue.get_and_lock_entries(locked_at_minimum: 1.second.ago, user: @triage_worker)
    end
  end
end
