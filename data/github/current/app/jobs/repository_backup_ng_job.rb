# typed: true
# frozen_string_literal: true

class RepositoryBackupNgJob < ApplicationJob
  class InvalidRepositoryType < StandardError; end
  class RepositoryBackupFailed < StandardError; end
  class GitBackupUnavailable < StandardError; end
  class MismatchedChecksumError < StandardError; end

  CONCURRENT_BACKUPS_PER_FS = 25
  RETRYABLE_ERRORS = [RepositoryBackupFailed, GitBackupUnavailable, MismatchedChecksumError]

  # Git Backups Response Codes
  MISMATCHED_CHECKSUM_RESPONSE = 2
  LOST_RACE_RESPONSE = 5
  SERVICE_UNAVAILABLE_RESPONSE = 6

  queue_as :gitbackups_perform
  locked_by timeout: 1.hour, key: ->(job) { "#{job.arguments[1]}-#{job.arguments[0]}" }

  retry_on *T.unsafe(RETRYABLE_ERRORS) do |job, error|
    RepositoryBackupNgJob.record_retry(error.message, job.type)
  end

  retry_on GitHub::Restraint::UnableToLock, wait: 1.minute, attempts: 10 do |job, _error|
    RepositoryBackupNgJob.record_retry("restraint", job.type)
  end

  attr_reader :repository, :repo_id, :type, :wiki, :opts

  def self.record_retry(reason, type)
    GitHub.dogstats.increment("gitbackups.requeue", tags: ["reason:#{reason}", "type:#{type}"])
  end

  resolve_tenant_context do |repo_id, type|
    # Proxima doesn't have gists
    unless type == :gist
      Repositories::Public.resolve_tenant(id: repo_id)
    end
  end

  def perform(repo_id, type, opts = {})
    # We enqueue gists with a nil ID due to the way we write to them before
    # they exist in the database. Just ignore those.
    return if repo_id.nil?

    @repo_id = repo_id
    @type    = type.to_s
    @wiki    = (@type == "wiki")
    @opts    = opts.with_indifferent_access
    @repository = find_repo_by_type

    Failbot.push app: "gitbackups"

    # If we've archived the repository, there's nothing to do, just return.
    if repository.nil?
      return if archived?

      # At this point it's mostly spam anon gists at a high rate, let's not report to Failbot
      GitHub.dogstats.increment("gitbackups.repository-not-found", { tags: ["type:#{type}"] })
      return
    end

    return unless repository.exists_on_disk?
    return if wiki && !repository.unsullied_wiki.exist?

    setup_backup_context
    log(type: type) do
      restraint.lock!(restraint_key, CONCURRENT_BACKUPS_PER_FS, 1.hour) do
        log(message: "starting git backup")

        result = if wiki
          repository.backup_wiki_ng!
        else
          repository.backup_ng!
        end

        delay_type = @opts[:delay] || "none"
        log(message: "completed git backup attempt",
            success: result.present? && result[:ok],
            delay: delay_type,
            since_pushed_at_ms: @opts[:pushed_at] ? GitHub::Dogstats.duration(@opts[:pushed_at]) : nil)
        GitHub.dogstats.timing_since("gitbackups.perform.since_pushed_at", @opts[:pushed_at], tags: ["type:#{type}", "delay:#{delay_type}"]) if @opts.key? :pushed_at

        # If backups aren't enabled but we got called, or if the
        # repository has disappeared between getting enqueued and us
        # running, consider it a failure and move on.
        if result.nil?
          GitHub.dogstats.increment("gitbackups.failure", { tags: ["type:#{type}"] })
          return
        end

        if result[:ok]
          GitHub.dogstats.increment("gitbackups.success", { tags: ["type:#{type}"] })
        else
          out, err = result[:out], result[:err]
          Failbot.push stdout: out, stderr: err

          GitHub.dogstats.increment("gitbackups.failure", { tags: ["type:#{type}"] })

          if result[:status] == MISMATCHED_CHECKSUM_RESPONSE
            # git-backup returns 2 when when it notices that an on-disk checksum does
            # not match the repository state. We want an accurate checksum so we enqueue
            # a fix so we can try later.
            if repository.is_a?(Gist)
              SpokesRecomputeGistChecksumsJob.perform_later(repository.id)
            else
              SpokesRecomputeChecksumsJob.perform_later(repository.id, wiki)
            end
            GitHub.dogstats.increment("gitbackups.mismatched_checksum", { tags: ["type:#{type}"] })
            raise MismatchedChecksumError, "mismatched-checksum"
          elsif result[:status] == LOST_RACE_RESPONSE
            # git-backup detected that we've lost a race to perform a
            # backup. If the other concurrency controls don't stop us from
            # performing concurrent backups on a repository, we can detect
            # it when we're about to commit the incremental. We can ignore
            # it as the backup is as recent as the one we were trying to
            # make.
            GitHub.dogstats.increment("gitbackups.concurrent-backup", { tags: ["type:#{type}"] })
          elsif result[:status] == SERVICE_UNAVAILABLE_RESPONSE
            # git-backup has asked to try again later because some service
            # is unavailable. No need to be noisy about it.
            raise GitBackupUnavailable, "unavailable"
          else
            raise RepositoryBackupFailed, "failure"
          end
        end
      end
    end # log
  rescue GitHub::DGit::UnroutedError
    # When a repo record has been destroyed, the fetched record is still
    # available, but Repository#network relationship fails. Die
    # gracefully.
    nil
  end

  def log(data, &blk)
    GitHub::Logger.log_context(job: self.class.to_s, spec: repository.dgit_spec) do
      GitHub::Logger.log(data, &blk)
    end
  end

  def find_repo_by_type
    case @type
    when "repository", "wiki"
      Repositories.domain.by_id(repo_id)
    when "gist"
      if repo_id.is_a? Numeric
        Gist.find_by(id: repo_id)
      else
        Gist.find_by(repo_name: repo_id)
      end
    else
      raise InvalidRepositoryType, type
    end
  end

  def setup_backup_context
    case type
    when "repository", "wiki"
      Failbot.push alternates: repository.shared_storage_enabled?,
                    networked: repository.network.shared_storage_enabled?,
                    backup_type: type,
                    spec: repository.dgit_spec(wiki: type == "wiki")
    when "gist"
      Failbot.push owner: repository.user_param,
                    backup_type: type,
                    spec: repository.dgit_spec
    else
      raise InvalidRepositoryType, type
    end
  end

  def archived?
    case type
    when "repository", "wiki", "gist"
      false
    else
      raise InvalidRepositoryType, type
    end
  end

  def restraint
    @restraint ||= GitHub::Restraint.new
  end

  def restraint_key
    "backups_#{repository.route}"
  end
end
