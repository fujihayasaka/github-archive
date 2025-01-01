# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamParentChangePendingQueueTest < GitHub::TestCase

  def move(team_id:, from:, to:, descendants:)
    Team::ParentChange::Payload.new(team_id: team_id, old_path: from, new_path: to, old_descendants: descendants)
  end

  fixtures do
    @org_id = create(:organization).id
  end

  setup do
    @queue = Team::ParentChange::PendingQueue.new(org_id: @org_id)
  end

  test "basic workflow: enqueue, peek and dequeue" do
    first_change  = move(team_id: 3, from: "",    to: "1/2", descendants: [4, 5, 6])
    second_change = move(team_id: 3, from: "1/2", to: "9",   descendants: [4, 5, 6])

    @queue.enqueue first_change
    assert_equal first_change, @queue.peek

    @queue.enqueue second_change
    assert_equal first_change, @queue.peek

    dequeued = @queue.dequeue
    assert_equal first_change, dequeued

    dequeued = @queue.dequeue
    assert_equal second_change, dequeued

    assert_nil @queue.peek
    assert_nil @queue.dequeue

    refute @queue.exist?
  end

  test "displays queue" do
    assert_equal [], @queue.to_a

    first_change  = move(team_id: 3, from: "",    to: "1/2", descendants: [4, 5, 6])
    second_change = move(team_id: 3, from: "1/2", to: "9",   descendants: [4, 5, 6])

    @queue.enqueue first_change
    @queue.enqueue second_change

    assert_equal [first_change, second_change], @queue.to_a
  end

  test "queueing too many jobs raises an exception" do
    assert_equal [], @queue.to_a

    first_change  = move(team_id: 3, from: "",    to: "1/2", descendants: [4, 5, 6])
    second_change = move(team_id: 3, from: "1/2", to: "9",   descendants: [4, 5, 6])

    @queue.enqueue first_change
    @queue.stubs(:max_bytes).returns(10)

    assert_raises(GitHub::DataStructures::PersistentAtomicQueue::OverflowError) do
      @queue.enqueue second_change
    end
  end
end
