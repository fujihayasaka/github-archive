# typed: true
# frozen_string_literal: true

require "test_helper"

class SecretScanIncrementalStatusTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
    @secret_scan_incremental_status = create(
      :secret_scan_incremental_status,
      repository: @repo,
      before_oid: "284761a04efd89d080767c5dada080ee3d956b7e",
      after_oid: "47c19e0f0e28187185cdcb933d33263d865481c0",
      ref_name: "refs/head/main",
      requested_at: Time.now
    )
  end

  context "validation and destruction" do
    test "requires a repository" do
      scan_status = SecretScanIncrementalStatus.new(repository_id: nil)

      refute_predicate scan_status, :valid?
      refute_empty scan_status.errors[:repository_id]
    end

    test "requires a valid scan state" do
      scan_status = SecretScanIncrementalStatus.new(scan_state: nil)
      refute_predicate scan_status, :valid?
      refute_empty scan_status.errors[:scan_state]
    end

    test "requires a default retry count" do
      scan_status = SecretScanIncrementalStatus.new(retry_count: nil)
      refute_predicate scan_status, :valid?
      refute_empty scan_status.errors[:retry_count]
    end

    test "requires a before oid" do
      scan_status = SecretScanIncrementalStatus.new(before_oid: nil)
      refute_predicate scan_status, :valid?
      refute_empty scan_status.errors[:before_oid]
    end

    test "requires an after oid" do
      scan_status = SecretScanIncrementalStatus.new(after_oid: nil)
      refute_predicate scan_status, :valid?
      refute_empty scan_status.errors[:after_oid]
    end

    test "requires a ref name" do
      scan_status = SecretScanIncrementalStatus.new(ref_name: nil)
      refute_predicate scan_status, :valid?
      refute_empty scan_status.errors[:ref_name]
    end

    test "requires a requested_at timestamp" do
      scan_status = SecretScanIncrementalStatus.new(requested_at: nil)
      refute_predicate scan_status, :valid?
      refute_empty scan_status.errors[:requested_at]
    end

    test "is deleted after repository destruction" do
      assert_difference("SecretScanIncrementalStatus.count", 0) do
        @repo.destroy
      end
    end
  end

  context "ensure create status entry for repository" do
    test "creates status entry for repo" do
      repo1 = create(:repository)
      refs = [
        ["184761a04efd89d080767c5dada080ee3d956b7e", "384761a04efd89d080767c5dada080ee3d956b7e", "refs/head/main"],
        ["584761a04efd89d080767c5dada080ee3d956b7e", "784761a04efd89d080767c5dada080ee3d956b7e", "refs/head/gh"]
      ]

      assert_empty repo1.secret_scan_incremental_statuses

      SecretScanIncrementalStatus.create_status_entries_for_repo!(repo1, refs)

      assert_equal 2, repo1.secret_scan_incremental_statuses.count

      repo1.secret_scan_incremental_statuses.each do |status|
        assert_equal "requested", status.scan_state
        refute_nil status.requested_at
        assert_nil status.scanned_at
      end
    end
  end

  context "update status entry for incremental scan" do
    test "updates status entry for incremental scan with scheduled and completed status" do
      assert_equal "requested", @repo.secret_scan_incremental_statuses.first.scan_state

      @secret_scan_incremental_status.update_queued_scan_state!
      @repo.reload

      assert_equal @secret_scan_incremental_status.attributes, @repo.secret_scan_incremental_statuses.first.attributes
      assert_equal "scheduled", @repo.secret_scan_incremental_statuses.first.scan_state
      assert_nil @repo.secret_scan_incremental_statuses.first.scanned_at

      @secret_scan_incremental_status.update_completed_scan_state!
      @repo.reload

      assert_equal @secret_scan_incremental_status, @repo.secret_scan_incremental_statuses.first
      assert_equal "completed", @repo.secret_scan_incremental_statuses.first.scan_state
      refute_nil @repo.secret_scan_incremental_statuses.first.scanned_at
    end
  end

  context "update failed scan state for status entry" do
    test "updates failed state with given retry count when passed in" do
      assert_equal "requested", @repo.secret_scan_incremental_statuses.first.scan_state

      @secret_scan_incremental_status.update_failed_scan_state!(:failed_execution)
      @secret_scan_incremental_status.update_queued_scan_state!
      @repo.reload

      assert_equal 1, @repo.secret_scan_incremental_statuses.first.retry_count

      @secret_scan_incremental_status.update_failed_scan_state!(:failed_retry_count_exceeded, 500)
      @repo.reload

      assert_equal 500, @repo.secret_scan_incremental_statuses.first.retry_count
      assert_equal "failed_retry_count_exceeded", @repo.secret_scan_incremental_statuses.first.scan_state
    end
  end

  context "update retry count for status entry" do
    test "updates retry count for incremental scan which is already scheduled and eventually fails terminally" do
      assert_equal "requested", @repo.secret_scan_incremental_statuses.first.scan_state

      @secret_scan_incremental_status.update_queued_scan_state!
      @repo.reload

      assert_equal @secret_scan_incremental_status.attributes, @repo.secret_scan_incremental_statuses.first.attributes
      assert_equal "scheduled", @repo.secret_scan_incremental_statuses.first.scan_state
      assert_nil @repo.secret_scan_incremental_statuses.first.scanned_at
      assert_equal 0, @repo.secret_scan_incremental_statuses.first.retry_count

      @secret_scan_incremental_status.update_queued_scan_state!
      @repo.reload

      assert_equal "scheduled", @repo.secret_scan_incremental_statuses.first.scan_state
      assert_equal 1, @repo.secret_scan_incremental_statuses.first.retry_count

      @secret_scan_incremental_status.update_queued_scan_state!
      @repo.reload

      assert_equal "scheduled", @repo.secret_scan_incremental_statuses.first.scan_state
      assert_equal 2, @repo.secret_scan_incremental_statuses.first.retry_count

      @secret_scan_incremental_status.update_queued_scan_state!
      @repo.reload

      assert_equal "scheduled", @repo.secret_scan_incremental_statuses.first.scan_state
      assert_equal 3, @repo.secret_scan_incremental_statuses.first.retry_count

      @secret_scan_incremental_status.update_queued_scan_state!
      @repo.reload

      assert_equal "scheduled", @repo.secret_scan_incremental_statuses.first.scan_state
      assert_equal 4, @repo.secret_scan_incremental_statuses.first.retry_count

      @secret_scan_incremental_status.update_queued_scan_state!
      @repo.reload

      assert_equal "scheduled", @repo.secret_scan_incremental_statuses.first.scan_state
      assert_equal 5, @repo.secret_scan_incremental_statuses.first.retry_count

      @secret_scan_incremental_status.update_queued_scan_state!
      @repo.reload

      # Changes state to retry count exceeded on third retry
      assert_equal @secret_scan_incremental_status, @repo.secret_scan_incremental_statuses.first
      assert_equal "failed_retry_count_exceeded", @repo.secret_scan_incremental_statuses.first.scan_state
      assert_equal 6, @repo.secret_scan_incremental_statuses.first.retry_count
    end

    test "updates retry count for incremental scan which is failing and eventually fails terminally" do
      assert_equal "requested", @repo.secret_scan_incremental_statuses.first.scan_state

      @secret_scan_incremental_status.update_queued_scan_state!
      @repo.reload

      assert_equal @secret_scan_incremental_status.attributes, @repo.secret_scan_incremental_statuses.first.attributes
      assert_equal "scheduled", @repo.secret_scan_incremental_statuses.first.scan_state
      assert_nil @repo.secret_scan_incremental_statuses.first.scanned_at
      assert_equal 0, @repo.secret_scan_incremental_statuses.first.retry_count

      @secret_scan_incremental_status.update_failed_scan_state!(:failed_execution)
      @secret_scan_incremental_status.update_queued_scan_state!
      @repo.reload

      assert_equal "scheduled", @repo.secret_scan_incremental_statuses.first.scan_state
      assert_equal 1, @repo.secret_scan_incremental_statuses.first.retry_count

      @secret_scan_incremental_status.update_failed_scan_state!(:failed_capacity_unavailable)
      @secret_scan_incremental_status.update_queued_scan_state!
      @repo.reload

      assert_equal "scheduled", @repo.secret_scan_incremental_statuses.first.scan_state
      assert_equal 2, @repo.secret_scan_incremental_statuses.first.retry_count

      @secret_scan_incremental_status.update_failed_scan_state!(:failed_execution)
      @secret_scan_incremental_status.update_queued_scan_state!
      @repo.reload

      assert_equal "scheduled", @repo.secret_scan_incremental_statuses.first.scan_state
      assert_equal 3, @repo.secret_scan_incremental_statuses.first.retry_count

      @secret_scan_incremental_status.update_failed_scan_state!(:failed_capacity_unavailable)
      @secret_scan_incremental_status.update_queued_scan_state!
      @repo.reload

      assert_equal "scheduled", @repo.secret_scan_incremental_statuses.first.scan_state
      assert_equal 4, @repo.secret_scan_incremental_statuses.first.retry_count

      @secret_scan_incremental_status.update_failed_scan_state!(:failed_capacity_unavailable)
      @secret_scan_incremental_status.update_queued_scan_state!
      @repo.reload

      assert_equal "scheduled", @repo.secret_scan_incremental_statuses.first.scan_state
      assert_equal 5, @repo.secret_scan_incremental_statuses.first.retry_count

      @secret_scan_incremental_status.update_failed_scan_state!(:failed_capacity_unavailable)
      @secret_scan_incremental_status.update_queued_scan_state!
      @repo.reload

      # Changes state to retry count exceeded on third retry
      assert_equal @secret_scan_incremental_status, @repo.secret_scan_incremental_statuses.first
      assert_equal "failed_retry_count_exceeded", @repo.secret_scan_incremental_statuses.first.scan_state
      assert_equal 6, @repo.secret_scan_incremental_statuses.first.retry_count
    end
  end
end
