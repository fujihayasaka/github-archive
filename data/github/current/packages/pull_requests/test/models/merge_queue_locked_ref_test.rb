# typed: true
# frozen_string_literal: true

require "test_helper"

class MergeQueueLockedRefTest < GitHub::TestCase
  fixtures do
    @entry = create(:merge_queue_entry)
    @queue = @entry.queue
    @fork_entry = create(:merge_queue_entry)
  end

  context "validations" do
    test "requires a repository" do
      MergeQueueLockedRef.destroy_all
      locked_ref = MergeQueueLockedRef.create_for!(entry: @entry)
      assert_predicate locked_ref, :valid?

      locked_ref.repository = nil

      refute_predicate locked_ref, :valid?
      assert_includes locked_ref.errors[:repository], "must exist"
    end

    test "requires a queue" do
      MergeQueueLockedRef.destroy_all
      locked_ref = MergeQueueLockedRef.create_for!(entry: @entry)
      assert_predicate locked_ref, :valid?

      locked_ref.queue = nil

      refute_predicate locked_ref, :valid?
      assert_includes locked_ref.errors[:queue], "must exist"
    end

    test "requires a ref" do
      MergeQueueLockedRef.destroy_all
      locked_ref = MergeQueueLockedRef.create_for!(entry: @entry)
      assert_predicate locked_ref, :valid?

      locked_ref.ref = nil

      refute_predicate locked_ref, :valid?
      assert_includes locked_ref.errors[:ref], "can't be blank"
    end

    test "is unique by ref and queue per repository" do
      repository = @queue.repository

      MergeQueueLockedRef.destroy_all
      locked_ref = MergeQueueLockedRef.create_for!(entry: @entry)
      assert_predicate locked_ref, :valid?

      protected_branch = repository.protect_branch(
        "main",
        creator: repository.owner,
        required_linear_history: true,
        entry_point: :test_case,
      )

      second_merge_queue = MergeQueue.create!(
        branch: "main",
        repository: repository,
        protected_branch: protected_branch,
      )

      second_locked_ref = locked_ref.dup
      second_locked_ref.queue = second_merge_queue
      second_locked_ref.save!

      assert_predicate second_locked_ref, :valid?

      assert_raises(ActiveRecord::RecordInvalid) do
        MergeQueueLockedRef.create_for!(entry: @entry)
      end

      assert_raises(ActiveRecord::RecordInvalid) do
        MergeQueueLockedRef.create!(
          repository_id: repository.id,
          queue: second_merge_queue,
          ref: @entry.pull_request.head_ref,
        )
      end
    end
  end

  context ".create_for!" do
    test "creates a locked ref for an entry" do
      MergeQueueLockedRef.destroy_all
      locked_ref = MergeQueueLockedRef.create_for!(entry: @entry)

      assert_equal @queue.repository, locked_ref.repository
      assert_equal @queue, locked_ref.queue
      assert_equal @entry.pull_request.head_ref, locked_ref.ref
    end
  end

  context ".for" do
    test "returns record for entry" do
      MergeQueueLockedRef.destroy_all
      locked_ref = MergeQueueLockedRef.create_for!(entry: @entry)

      assert_equal locked_ref, MergeQueueLockedRef.for(entry: @entry)
    end

    test "returns nil if locked ref does not exist" do
      MergeQueueLockedRef.destroy_all
      assert_nil MergeQueueLockedRef.for(entry: @entry)
    end

    test "returns nil if entry is not specified" do
      assert_nil MergeQueueLockedRef.for(entry: nil)
    end
  end
end
