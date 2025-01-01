# typed: true
# frozen_string_literal: true

module GitHub
  module ToggleRepoPermission
    extend GitHub::CacheLock

    # Performs on-disk operations necessary when a repository's visibility
    # changes. This includes enabling and disabling network alternates which
    # can take some time to finish up.
    #
    # The job grabs a cache lock when it starts to ensure that people
    # switching repo visibility back and forth don't create a case where the
    # repository is being thrashed in repack and gc operations. Jobs run when
    # one is already running bail out.
    #
    # Repo visibility is checked again when the job completes. If it changed
    # while the operations were in progress, the job is requeued.
    def self.perform(repo, detach = false)
      visibility = repo.visibility

      # obtain a lock on manipulating the repo on disk or bail out. then
      # perform the heavy operations.
      cache_lock "lock:toggle-perm:#{repo.id}", 1.hour do
        repo.detach!(synchronous: true) if detach && repo.network.repositories.count + repo.network.deleted_repositories.count > 1
        repo.reload_network
        repo.enable_or_disable_shared_storage if repo.public?
        repo.network.enable_or_disable_shared_storage_for_private_repositories

        repo.update_organization

        # close any pull requests sent from this repo on public repositories
        if repo.private?
          repo.pull_requests_as_head.open_pulls.each do |pull|
            next if pull.repository.private?
            pull.close(repo.owner)
          end
        end

        # now check to see if the repo permission was toggled into some other
        # state while we were working. if so, queue up another toggle job.
        repo.reload
        if repo.visibility != visibility
          repo.async_toggle_repository_visibility(actor: @options[:actor] || repo.owner, old_visibility: visibility)

        # repo permissions were not toggled into some other state, so update
        # the search index
        else
          # check if this repo or any of the owner's other repos should be
          # unlocked as a result of this visibility change
          repo.owner.update_locked_repositories

          # update visibility in the search indexes
          repo.reindex_all

          # update the public repository count for the owner in the search index
          repo.owner.synchronize_search_index
        end

        repo.calculate_network_counts!
      end
    end
  end
end
