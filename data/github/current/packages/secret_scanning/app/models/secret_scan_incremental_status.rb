# typed: true
# frozen_string_literal: true

class SecretScanIncrementalStatus < ApplicationRecord::TokenScanningService

  MAX_RETRY_COUNT = 5
  REF_UPDATES_BATCH_SIZE = 100

  belongs_to :repository

  validates_presence_of :repository_id, :before_oid, :after_oid, :ref_name, :requested_at, :scan_state, :retry_count

  scope :retry_eligible, -> { where(scan_state: [:scheduled, :failed_execution, :failed_capacity_unavailable]) }

  scope :within_threshold, ->(threshold) { where("updated_at > ?", Time.now - threshold) }

  scope :older_than_retry_threshold, ->(third_retry_threshold, fourth_retry_threshold, fifth_retry_threshold) {
    where("(updated_at < ? and retry_count <= 3) or (updated_at < ? and retry_count = 4) or (updated_at < ? and retry_count = 5)",
    Time.now - third_retry_threshold, Time.now - fourth_retry_threshold, Time.now - fifth_retry_threshold)
  }

  scope :older_than_completed_threshold, ->(threshold) { where("updated_at < ?", Time.now - threshold) }

  scope :ordered_by_scan_state_and_updated_time, -> { order(scan_state: :asc, updated_at: :asc) }

  enum :scan_state, {
    # Scan requested.
    requested: 0,

    # Scan materialized to a job.
    scheduled: 1,

    # Scan abandoned: Repo no longer qualifies for scan. Currently a terminal state.
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
  }

  # Update scan status of an entry to queued when scan is queued for the entry by the incremental scheduler
  def update_queued_scan_state!
    current_retry_count = update_retry_count
    if current_retry_count > MAX_RETRY_COUNT
      update_failed_scan_state!(:failed_retry_count_exceeded, current_retry_count)
    else
      update!(scan_state: :scheduled, retry_count: current_retry_count)
    end
  end

  # Update scan status of an entry to requested.
  def update_requested_scan_state!
    update!(scan_state: :requested, requested_at: Time.zone.now)
  end

  # Update scan status of an entry to completed when scan completes
  def update_completed_scan_state!
    update!(scan_state: :completed, scanned_at: Time.zone.now)
  end

  # Update scan status with a failed outcome
  def update_failed_scan_state!(outcome, current_retry_count = nil)
    update!(scan_state: outcome, retry_count: (current_retry_count || retry_count))
  end

  # Ensure the presence of an entries for refs in a repo, and create entries if not present.
  # If an entry is already present, reset scan state to 'requested'
  def self.ensure_status_entries_for_repo!(repo, ref_updates)
    ref_updates.in_groups_of(REF_UPDATES_BATCH_SIZE, false) do |group|
      throttle do
        group.each do |ref|
          retry_on_find_or_create_error do
            find_status_entry_by_repo_ref(repo.id, ref.first, ref.second) || create_status_entry_for_repo!(repo, ref)
          end
        end
      end
    end
  end

  # Creates one entry per changed ref in a repo, with a default scan status of requested.
  def self.create_status_entries_for_repo!(repo, ref_updates)
    ref_updates.in_groups_of(REF_UPDATES_BATCH_SIZE, false) do |group|
      throttle do
        group.each do |ref|
          create_status_entry_for_repo!(repo, ref)
        end
      end
    end
  end

  # Creates a status entry for a repo-ref combination
  def self.create_status_entry_for_repo!(repo, ref)
    create!(
       repository: repo,
       before_oid: ref.first,
       after_oid: ref.second,
       ref_name: ref.third,
       requested_at: Time.now
     )
  end
  private_class_method :create_status_entry_for_repo!

  # Finds an entry in the table for the repo-ref combination.
  def self.find_status_entry_by_repo_ref(repo_id, before_oid, after_oid)
    ActiveRecord::Base.connected_to(role: :reading) do
      find_by(repository_id: repo_id, before_oid: before_oid, after_oid: after_oid)
    end
  end
  private_class_method :find_status_entry_by_repo_ref

  # Batch size for processing ref updates.
  def self.ref_updates_batch_size
    REF_UPDATES_BATCH_SIZE
  end

  private

  # Bumps retry count by 1 if scan has already been scheduled, or is in a non-terminal failure state.
  def update_retry_count
    current_retry_count = retry_count
    if scan_state != "requested"
      current_retry_count = current_retry_count + 1
    end
    current_retry_count
  end

  def scan_scope
    "commit"
  end
end
