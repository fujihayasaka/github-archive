# typed: true
# frozen_string_literal: true

class Repository::NetworkGraph < ApplicationRecord::Collab
  extend T::Helpers

  include GitHub::ResilienceMixin

  JOB_STATUS_TTL = 2.hours

  belongs_to :repository

  validates :repository, presence: true
  validates :repository_id, uniqueness: true

  # Public: Finds or creates a network graph record for the given repo.
  #
  # Returns a Repository::NetworkGraph.
  def self.for_repository(repo)
    already_retried ||= T.let(false, T::Boolean)

    ActiveRecord::Base.connected_to(role: :writing) do
      where(repository: repo).first || create!(repository: repo)
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    raise if already_retried

    already_retried = true
    retry
  end

  def meta_json
    if meta
      @meta_json ||= Zlib::Inflate.inflate(meta)
    end
  end

  def data_json(start_time, end_time)
    return GitHub::JSON.encode(commits: []) unless commits_index && commits_data && focus
    commit_data = Zlib::Inflate.inflate(commits_data)
    index_data  = Zlib::Inflate.inflate(commits_index)
    GitHub::JSON.encode(commits: GraphBuilder.extract_commits(index_data, commit_data, focus, start_time, end_time))
  end

  def current?
    return false unless network_hash?
    current_network_hash == network_hash
  end

  def build
    return if current? || running?
    enqueue_network_graph_job
  end

  def force_build
    clear!
    build
  end

  def build!
    clear!
    hash = current_network_hash
    GitHub.dogstats.time "netgraph", tags: ["action:build"] do
      meta_data, index_data, commits_data = GraphBuilder.new(repository, hash).build
      update(
        focus:         meta_data["focus"],
        meta:          Zlib::Deflate.deflate(GitHub::JSON.encode(meta_data)),
        commits_index: Zlib::Deflate.deflate(index_data),
        commits_data:  Zlib::Deflate.deflate(commits_data),
        network_hash:  hash,
        built_at:      Time.now,
      )
    end
  end

  def current_network_hash
    @current_network_hash ||= Digest::SHA256.hexdigest(repository&.network&.repositories&.maximum(:pushed_at).to_i.to_s)
  end

  def running?
    job_status&.pending? || job_status&.started?
  end

  private

  def clear!
    return if built_at.nil?
    update(
      focus:         nil,
      meta:          nil,
      commits_index: nil,
      commits_data:  nil,
      network_hash:  nil,
      built_at:      nil,
    )
  end

  def job_status
    return @job_status if defined?(@job_status)

    @job_status = with_database_error_fallback(fallback: nil) do
      JobStatus.find(job_status_id)
    end

    set_ttl_for_legacy_job_status

    @job_status
  end

  # Internal: JobStatuses created prior to this method being added had no ttl which means they
  # never expired if the job never ran. This resulted in graphs whose jobs were discarded from
  # ever having their data generated.
  def set_ttl_for_legacy_job_status
    return unless job_status

    # nothing to do if the ttl is already the expected value
    return if job_status.ttl == JOB_STATUS_TTL

    job_status.ttl = JOB_STATUS_TTL

    ActiveRecord::Base.connected_to(role: :writing) do
      job_status.save
    end
  end

  def enqueue_network_graph_job
    create_job_status
    RepositoryNetworkGraphBuilderJob.perform_later(repository_network_graph_id: self.id)
    true
  end

  def create_job_status
    ActiveRecord::Base.connected_to(role: :writing) do
      job_id = SecureRandom.uuid

      # create a new job status and update the cache ivar used in #job_status
      @job_status = with_database_error_fallback(fallback: nil) do
        JobStatus.create(id: job_id, ttl: JOB_STATUS_TTL)
      end

      self.update! job_status_id: job_id if @job_status
      return @job_status
    end
  end

  # Return the repos associated with the network using #network_repos_for.
  # Don't include private repos, repos where the original repo owner owns
  # the associated repo, repos that have not been pushed to. Finally,
  # sort the repos by how many stars they have and when they were most
  # recently pushed to.
  def network_repos
    @network_repos ||= begin
      other_repos = T.must(repository).network_repositories.not_spammy
      other_repos = other_repos
        .where(["repositories.pushed_at > repositories.created_at AND repositories.id <> ?", repository&.id])
        .order("repositories.pushed_at DESC")
        .limit(GitHub.network_graph_fork_limit)
        .to_a

      if T.must(repository).private? && T.must(repository).owner&.user?
        other_repos.select! { |repo| repo.pullable_by?(T.must(repository).owner) }
      end

      # Return an array including the base repo, as well as the other repos.
      [repository] + other_repos
    end
  end
end
