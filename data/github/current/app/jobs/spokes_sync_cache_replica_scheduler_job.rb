# typed: true
# frozen_string_literal: true

class SpokesSyncCacheReplicaSchedulerJob < ApplicationJob
  queue_as :dgit_schedulers

  schedule(interval: 120.seconds, scope: :global)

  locked_by timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  exempt_from_tenant_context_requirement

  def self.enabled?
    GitHub.enterprise?
  end

  # Run every interval, schedules jobs_per_interval maintenance jobs to run.
  def perform
    Failbot.push app: "github-dgit"
    ctx = GitHub::DGit::Maintenance::NetworkMaintenanceContext.new

    SlowQueryLogger.disabled do
      out_of_sync_replicas = self.class.get_out_of_sync_cache_replicas
      out_of_sync_replicas.each do |repo_id, host, repo_type|
        next unless ctx.ok_to_queue_job?(host, increment: true)
        sync_cache_replica(repo_id, repo_type, host)
      end
    end
  end

  # Queue a job to sync one cache replica
  #   - repo_id         = the repo whose replica to repair
  #   - repo_type       = type of repo
  #   - host            = which replica to repair
  def sync_cache_replica(repo_id, repo_type, host)
    is_wiki = (repo_type == GitHub::DGit::RepoType::WIKI)
    SpokesSyncCacheReplicaJob.set(queue: "maint_#{host}").perform_later(repo_id, host, is_wiki)
  end

  def self.get_out_of_sync_cache_replicas
    limit = GitHub::DGit::Maintenance.network_query_limit

    mismatches_found = begin
      results = T.let([], T::Array[T.untyped])

      cache_servers = T.let([], T::Array[T.untyped])
      GitHub::DGit::DB.each_fileserver_db do |db|
        cache_servers |= db.SQL.results("SELECT host FROM fileservers WHERE cache_location IS NOT NULL").flatten
      end
      return [] if cache_servers.empty?

      GitHub::DGit::DB.each_network_db do |db|
        sql = db.SQL.new \
                       limit: limit
        sql.add <<-SQL
          SELECT rr.repository_id,
                 rr.host,
                 rr.repository_type
            FROM repository_replicas rr
            JOIN repository_checksums rc
              ON rr.repository_id = rc.repository_id
             AND rr.repository_type = rc.repository_type
             AND rr.checksum != CONCAT("cache:", rc.checksum)
             AND rr.checksum != "ok"
        SQL

        sql.add "AND rr.host IN :cache_servers", cache_servers: cache_servers
        sql.add "LIMIT :limit"
        results |= sql.results
      end # each_network_db
      results
    end

    return [] if mismatches_found.empty?
    mismatches_found
  end
end
