# typed: false
# frozen_string_literal: true

# Moves objects and refs pushed into an alternated repository to the
# shared storage area in network.git, synchronizing all objects and refs.
#
# See the docs on repository storage for more information on
# synchronization and shared object storage:
#
# https://thehub.github.com/engineering/development-and-ops/dotcom/repository-storage/
#
# This job is enqueued from the RepositoryPush job and runs at most one
# process per repository.
#
# See the git-nw-sync manual for more information on what happens on the
# fs backend:
#
#     https://github.com/github/gitrpcd/blob/master/docs/man/nw/git-nw-sync.1.ronn
class RepositorySyncJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :repository_sync

  # Exception raised when the job fails due to git command failure.
  class Failed < StandardError
  end

  class InsufficientQuorum < StandardError; end
  retry_on InsufficientQuorum, wait: :polynomially_longer

  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  resolve_tenant_context do |repo_id|
    Repositories::Public.resolve_tenant(id: repo_id)
  end

  # Perform the sync of objects and refs into network.git.
  #
  # repo_id - The integer repository id.
  #
  # Returns nothing.
  def perform(repo_id)
    repository = Repository.find_by_id(repo_id)
    return if repository.nil?

    # give failbot some additional context for exception reports
    Failbot.push "gh.spokes.spec": repository.dgit_spec,
      "gh.repo.shared_storage_enabled": repository.shared_storage_enabled?

    # if a backup-utils backup is in progress, delay the sync operation by
    # requeuing after a short sleep period.
    if GitHub::Enterprise.backup_in_progress?
      clear_lock
      repository.synchronize_shared_storage
      sleep 1
      return
    end

    GitHub.dogstats.time "repository", tags: ["action:synchronize_shared_storage", "via:job"] do
      repository.synchronize_shared_storage!
    end
  rescue GitRPC::CommandFailed => boom
    # It is expected that sometimes this job will fail to acquire the nw-sync lock on a repo.
    # If this is the case, we do not need to raise an error that will be reported.
    return if boom.message =~ /fatal: could not get the nw-sync lock/

    raise RepositorySyncJob::Failed, "Failed to GC repository: #{boom.message}"
  rescue Repository::CommandFailed => boom
    raise RepositorySyncJob::Failed, "Failed to GC repository: #{boom.message}"
  rescue GitRPC::Protocol::DGit::ResponseError => boom
    if boom.message.include?("Backend insufficient quorum")
      raise InsufficientQuorum.new(boom)
    else
      raise
    end
  end
end
