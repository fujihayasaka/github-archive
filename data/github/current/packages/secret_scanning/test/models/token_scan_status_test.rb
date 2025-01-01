# typed: true
# frozen_string_literal: true

require "test_helper"

class TokenScanStatusTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
    @token_scan_status = create(:token_scan_status, repository: @repo)
  end

  context "validation and destruction" do
    test "requires a repository" do
      repo_status = TokenScanStatus.new(repository_id: nil)

      refute_predicate repo_status, :valid?
      refute_empty repo_status.errors[:repository_id]
    end

    test "requires a valid scan state" do
      repo_status = TokenScanStatus.new(scan_state: nil)
      refute_predicate repo_status, :valid?
      refute_empty repo_status.errors[:scan_state]
    end

    test "requires a default retry count" do
      repo_status = TokenScanStatus.new(retry_count: nil)
      refute_predicate repo_status, :valid?
      refute_empty repo_status.errors[:retry_count]
    end

    test "is deleted after repository destruction " do
      assert_difference("TokenScanStatus.count", -1) do
        @repo.destroy
      end
    end
  end

  context "ensure create status entry for repository" do
    test "creates status entry for repo" do
      repo1 = create(:repository)

      assert_nil repo1.token_scan_status

      TokenScanStatus.ensure_status_entry_for_repo!(repo1)

      assert_equal "performed_by_token_scanning_service", repo1.token_scan_status.scan_state
      assert_nil repo1.token_scan_status.scheduled_at
      assert_nil repo1.token_scan_status.scanned_at
    end

    test "creates status entry for repo queued by moda" do
      repo1 = create(:repository)

      assert_nil repo1.token_scan_status

      TokenScanStatus.ensure_status_entry_for_repo!(repo1)

      assert_equal "performed_by_token_scanning_service", repo1.token_scan_status.scan_state
      assert_nil repo1.token_scan_status.scheduled_at
      assert_nil repo1.token_scan_status.scanned_at
    end
  end

  context "update status entry for repository" do
    test "updates status entry for repository with scheduled and completed status" do
      assert_equal "requested", @repo.token_scan_status.scan_state

      @token_scan_status.update_queued_scan_state!
      @repo.reload

      assert_equal @token_scan_status.attributes, @repo.token_scan_status.attributes
      assert_equal "scheduled", @repo.token_scan_status.scan_state
      refute_nil @repo.token_scan_status.scheduled_at
      assert_nil @repo.token_scan_status.scanned_at

      @token_scan_status.update_completed_scan_state!
      @repo.reload

      assert_equal @token_scan_status , @repo.token_scan_status
      assert_equal "completed", @repo.token_scan_status.scan_state
      refute_nil @repo.token_scan_status.scheduled_at
      refute_nil @repo.token_scan_status.scanned_at
    end
  end

  context "update failed scan state for repository with failing scans" do
    test "updates failed state with given retry count when passed in" do
      assert_equal "requested", @repo.token_scan_status.scan_state

      @token_scan_status.update_failed_scan_state!(:failed_execution)
      @token_scan_status.update_queued_scan_state!
      @repo.reload

      assert_equal 1, @repo.token_scan_status.retry_count

      @token_scan_status.update_failed_scan_state!(:failed_retry_count_exceeded, 500)
      @repo.reload

      assert_equal 500, @repo.token_scan_status.retry_count
      assert_equal "failed_retry_count_exceeded", @repo.token_scan_status.scan_state
    end
  end

  context "update retry count for status entry for repository" do
    test "updates retry count for repository which is already scheduled and eventually fails terminally" do
      assert_equal "requested", @repo.token_scan_status.scan_state

      @token_scan_status.update_queued_scan_state!
      @repo.reload

      assert_equal @token_scan_status.attributes, @repo.token_scan_status.attributes
      assert_equal "scheduled", @repo.token_scan_status.scan_state
      refute_nil @repo.token_scan_status.scheduled_at
      assert_nil @repo.token_scan_status.scanned_at
      assert_equal 0, @repo.token_scan_status.retry_count

      @token_scan_status.update_queued_scan_state!
      @repo.reload

      assert_equal "scheduled", @repo.token_scan_status.scan_state
      assert_equal 1, @repo.token_scan_status.retry_count

      @token_scan_status.update_queued_scan_state!
      @repo.reload

      assert_equal "scheduled", @repo.token_scan_status.scan_state
      assert_equal 2, @repo.token_scan_status.retry_count

      @token_scan_status.update_queued_scan_state!
      @repo.reload

      assert_equal "scheduled", @repo.token_scan_status.scan_state
      assert_equal 3, @repo.token_scan_status.retry_count

      @token_scan_status.update_queued_scan_state!
      @repo.reload

      # Changes state to retry count exceeded on third retry"
      assert_equal @token_scan_status , @repo.token_scan_status
      assert_equal "failed_retry_count_exceeded", @repo.token_scan_status.scan_state
      assert_equal 4, @repo.token_scan_status.retry_count
    end

    test "updates retry count for repository which is failing and eventually fails terminally" do
      assert_equal "requested", @repo.token_scan_status.scan_state

      @token_scan_status.update_queued_scan_state!
      @repo.reload

      assert_equal @token_scan_status.attributes, @repo.token_scan_status.attributes
      assert_equal "scheduled", @repo.token_scan_status.scan_state
      refute_nil @repo.token_scan_status.scheduled_at
      assert_nil @repo.token_scan_status.scanned_at
      assert_equal 0, @repo.token_scan_status.retry_count

      @token_scan_status.update_failed_scan_state!(:failed_execution)
      @token_scan_status.update_queued_scan_state!
      @repo.reload

      assert_equal "scheduled", @repo.token_scan_status.scan_state
      assert_equal 1, @repo.token_scan_status.retry_count

      @token_scan_status.update_failed_scan_state!(:failed_capacity_unavailable)
      @token_scan_status.update_queued_scan_state!
      @repo.reload

      assert_equal "scheduled", @repo.token_scan_status.scan_state
      assert_equal 2, @repo.token_scan_status.retry_count

      @token_scan_status.update_failed_scan_state!(:failed_execution)
      @token_scan_status.update_queued_scan_state!
      @repo.reload

      assert_equal "scheduled", @repo.token_scan_status.scan_state
      assert_equal 3, @repo.token_scan_status.retry_count

      @token_scan_status.update_failed_scan_state!(:failed_capacity_unavailable)
      @token_scan_status.update_queued_scan_state!
      @repo.reload

      # Changes state to retry count exceeded on third retry"
      assert_equal @token_scan_status , @repo.token_scan_status
      assert_equal "failed_retry_count_exceeded", @repo.token_scan_status.scan_state
      assert_equal 4, @repo.token_scan_status.retry_count
    end
  end
end
