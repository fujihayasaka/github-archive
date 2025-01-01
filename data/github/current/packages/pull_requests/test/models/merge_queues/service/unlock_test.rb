# typed: true
# frozen_string_literal: true

require "test_helper"

module MergeQueues
  class UnlockTest < GitHub::TestCase
    fixtures do
      make_trusted_oauth_apps_owner
      create(:merge_queue_integration)

      @repo = create(:repository, :has_merge_queue)
      @queue = @repo.default_merge_queue
      @user = create(:user)
      @repo.add_member @user, action: :write

      example_repo_snapshot
    end

    setup do
      skip unless GitHub.merge_queues_enabled?
      example_repo_restore
    end

    test "next group is locked" do
      entry = create(:merge_queue_entry, :locked, queue: @queue)
      result = Service::Unlock.new(@repo, @queue.branch, @queue).call(actor: @user)

      assert_equal Service::Unlock::Result::Success, result
      refute_predicate entry.reload, :locked?
    end

    test "next group is not locked" do
      create(
        :merge_queue_entry,
        queue: @queue,
        locked: false,
        state: Entry::State::Mergeable::VALUE,
        head_sha: "xxxxxx"
      )
      result = Service::Unlock.new(@repo, @queue.branch, @queue).call(actor: @user)

      assert_equal Service::Unlock::Result::NextGroupNotLocked, result
    end

    test "no entries" do
      result = Service::Unlock.new(@repo, @queue.branch, @queue).call(actor: @user)

      assert_equal Service::Unlock::Result::NextGroupEmpty, result
    end
  end
end
