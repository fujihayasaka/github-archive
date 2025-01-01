# typed: true
# frozen_string_literal: true

class TokenScanStatus < ApplicationRecord::TokenScanningService

  belongs_to :repository

  validates_presence_of :repository_id, :scan_state, :retry_count

  scope :retry_eligible, -> { where(scan_state: [:scheduled, :failed_execution, :failed_capacity_unavailable]) }

  scope :older_than_threshold, ->(threshold) { where("updated_at < ?", Time.now - threshold) }

  scope :ordered_by_scan_state, -> { order(scan_state: :asc) }

  enum :scan_state, {
    # Scan requested.
    requested: 0,

    # Scan materialized to a job.
    scheduled: 1,

    # Scan abandoned: Repo no longer qualifies for scan. Currently a terminal state. TODO:  Re-queue if admin behavior changes qualification.
    non_qualifying_repo: 2,

    # Scan completed successfully.
    completed: 3,

    # Scan abandoned: Failed at runtime. Currently a terminal state.
    failed_execution: 4,

    # Scan abandoned: Resources were unavailable to perform scan. Currently a terminal state.
    failed_capacity_unavailable: 5,

    # Scan abandoned indefinitely: Repeated failures after three retries. Terminal state. Needs manual investigation.
    failed_retry_count_exceeded: 6,

    # Scan partially completed: Max candidate matches were reached. Terminal state.
    max_candidate_matches_exceeded: 7,

    # Scan is to be managed by the token-scanning-service.
    # Upon success, the state will transition to "completed"
    # Upon failure, the state will transition to "schedule" to be retried by dotcom.
    #  - When a port of the token scan status scheduler happens, we may need to introduce
    #  another state/column to ensure moda is responsible for retries too
    performed_by_token_scanning_service: 8,
  }

  # Ensure the presence of an entry for a repository for token scan, if it does not already exist
  # Create an entry for a repository for token scan status with default state of requested
  def self.ensure_status_entry_for_repo!(repo)
    unless repo.token_scan_status
      initial_state = :performed_by_token_scanning_service
      TokenScanStatus.create!(repository: repo, scan_state: initial_state)
    end

    repo.token_scan_status
  end

  # Update scan status of a repo to queued when scan is queued for the repo by the scheduler
  def update_queued_scan_state!
    current_retry_count = update_retry_count
    if current_retry_count > 3
      update_failed_scan_state!(:failed_retry_count_exceeded, current_retry_count)
      Failbot.report(StandardError.new("Scan terminally failed as retry count exceeded"), repo_id: repository&.id)
    else
      update!(scan_state: :scheduled, scheduled_at: Time.zone.now, retry_count: current_retry_count)
    end
  end

  # Update scan status of a repo to completed when scan completes
  def update_completed_scan_state!
    current_moment = Time.zone.now
    update!(scan_state: :completed, scheduled_at: (scheduled_at || current_moment), scanned_at: current_moment)
  end

  # Update scan status with a non-success outcome
  def update_failed_scan_state!(outcome , current_retry_count = nil)
    update!(scan_state: outcome, retry_count: (current_retry_count || retry_count), updated_at: Time.now)
  end

  private

  # Bumps retry count by 1 if repo is in non-terminally failed or already scheduled state
  def update_retry_count
    current_retry_count = self.retry_count
    if scan_state != "requested"
      current_retry_count = current_retry_count + 1
    end
    current_retry_count
  end

  def scan_scope
    "repo"
  end
end
