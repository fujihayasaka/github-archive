# typed: true
# frozen_string_literal: true

class Media::Transition < ApplicationRecord::Domain::Assets
  # raised when trying to perform an operation on a repository network that no
  # longer exists.
  class MissingRepositoryNetworkError < StandardError
  end

  # raised when trying to perform an operation on a repository network that no
  # longer has an extant owner.
  class MissingRepositoryNetworkOwnerError < StandardError
  end

  # Maximum time to wait for database replication lag in creating
  # repository network records before destroying the transition record
  # which references a missing repository network.
  MAX_REPOSITORY_NETWORK_WAIT = 50.minutes

  self.table_name = :media_transitions


  enum :operation, { copying: 0, deleting: 1, restoring: 2 }

  belongs_to :repository_network
  belongs_to :repository_network_owner, class_name: "User"
  belongs_to :old_repository_network, class_name: "RepositoryNetwork"

  validates_presence_of :repository_network_id
  validates :operation, presence: true
  after_destroy :log_transition_results

  def self.by_network(network)
    find_by(repository_network_id: network)
  end

  def self.async_copy(old_network, new_network)
    return false unless Media::Blob.in_network?(old_network)
    create!(
      repository_network: new_network,
      repository_network_owner: new_network.owner,
      old_repository_network: old_network,
      operation: operations["copying"],
    ).async_perform
    true
  end

  def self.async_delete(network)
    return false unless Media::Blob.where.not(state: :archived).in_network?(network)
    # Skip if there is another deleting media transition in flight
    return false if Media::Transition.find_by(repository_network: network, operation: operations["deleting"]).present?

    create!(
      repository_network: network,
      repository_network_owner: network.root&.owner,
      operation: operations["deleting"],
    )
    true
  end

  def self.async_restore(network)
    return false unless Media::Blob.in_network?(network)

    unqueue_task(network, "deleting")

    create!(
      repository_network: network,
      repository_network_owner: network.owner,
      operation: operations["restoring"],
    ).async_perform
    true
  end

  def self.unqueue_task(network, type)
    tasks = self.where(
      "repository_network_id = :network_id OR old_repository_network_id = :network_id",
      network_id: network.id,
    ).
    where(operation: operations[type]).
    order(id: :asc)

    tasks.each &:destroy
  end

  # Public: Verifies that a given operation and blob match this transition.
  def verify_blob(op, blob)
    if op != operation
      return :operation
    end

    if !blob.is_a?(Media::Blob)
      return :not_blob
    end

    matching_network_id = case operation
    when "copying" then old_repository_network_id
    when "deleting" then repository_network_id
    else raise "Bad operation for transition #{id}: #{operation}"
    end

    if blob.repository_network_id != matching_network_id
      return :wrong_network
    end

    :ok
  end

  def earlier_transition?
    network_ids = [repository_network_id, old_repository_network_id]
    network_ids.compact!

    transition_id = self.class.where(
      "repository_network_id IN (?) OR old_repository_network_id IN (?)",
      network_ids, network_ids
    ).order("id ASC").pluck(:id).first

    if transition_id
      transition_id < id
    else
      false
    end
  end

  def async_perform
    options = { "id" => id }
    TransitionMediaBlobsJob.perform_later(options)
  end

  def perform
    return if earlier_transition?

    self.class.connection.update(Arel.sql(<<-SQL, id: id, run_at: current_time_from_proper_timezone))
      UPDATE media_transitions SET
        runs = runs + 1,
        run_at = :run_at
      WHERE id = :id
    SQL

    GitHub.dogstats.distribution_timing_since("lfs.transition_job.wait.dist.time", created_at, tags: datadog_tags)

    send("perform_#{operation}")

    if owner = repository_network_owner
      owner.rebuild_asset_status
    end

    destroy
  end

  private

  def perform_copying
    return if invalid_repository_network?(repository_network, repository_network_id, "destination")

    each_network_batch old_repository_network_id do |blobs|
      existing = Media::Blob.where(
        repository_network_id: repository_network_id,
        oid: blobs.map(&:oid),
      ).index_by(&:oid)

      Media::Blob.copy_for_network(
        self,
        blobs.reject { |b| existing[b.oid] || invalid_blob?(b) },
        repository_network,
      )
    end
  end

  def perform_deleting
    each_network_batch repository_network_id do |blobs|
      blobs.each &:archive
    end
  end

  def perform_restoring
    return if invalid_repository_network?(repository_network, repository_network_id)

    each_network_batch repository_network_id do |blobs|
      blobs.each &:unarchive
    end
  end

  def invalid_repository_network?(network, network_id, name = "")
    plan_owner = network&.root&.plan_owner
    return false unless network.nil? || plan_owner.nil?

    max_runs = (MAX_REPOSITORY_NETWORK_WAIT / QueueMediaTransitionJobsJob::SCHEDULE_INTERVAL).ceil
    return true if runs.to_i >= max_runs

    # By raising an error, we avoid our caller destroying the transition,
    # which should wait until after a sufficient number of attempts.
    name += " " unless name.empty?
    if network.nil?
      raise MissingRepositoryNetworkError, "No #{name}repository network: #{network_id}"
    else
      raise MissingRepositoryNetworkOwnerError, "No #{name}repository network plan owner: #{network_id}"
    end
  end

  def invalid_blob?(blob)
    if GitHub.storage_cluster_enabled?
      blob.storage_blob.nil?
    else
      blob.asset.nil?
    end
  end

  def log_transition_results
    log = {
      "Timestamp" => Time.now.iso8601,
      "code.namespace" => "Media::Transition",
      "code.function" => operation,
      "gh.repo.network.id" => repository_network_id,
      "gh.media.transition.id" => id,
      "gh.media.transition.runs" => runs,
      "gh.media.transition.created_at" => created_at&.iso8601,
    }

    unless old_repository_network_id.nil?
      log[:"gh.media.transition.old_repository_network.id"] = old_repository_network_id
    end

    unless run_at.nil?
      log[:"gh.media.transition.run_at"] = T.must(run_at).iso8601
    end

    GitHub::Logger.info(log)
  end

  def each_network_batch(network_id, readonly: false)
    update!(last_blob_id: 0) if last_blob_id.nil?
    current_last_id = last_blob_id
    Media::Blob.each_network_batch(network_id, last_id: current_last_id, readonly: readonly) do |blobs|
      Media::Blob.throttle { yield blobs }
      current_last_id = T.cast(blobs.map(&:id).max, Integer)
      GitHub.dogstats.count("lfs.transitions.blobs", blobs.size, tags: datadog_tags)
    end
  ensure
    update!(last_blob_id: current_last_id.to_i)
  end

  def datadog_tags
    @datadog_tags ||= ["op:#{operation}"]
  end
end
