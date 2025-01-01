# typed: true
# frozen_string_literal: true

module Repository::StaffTools
  extend T::Helpers

  requires_ancestor { Repository }

  def make_network_root
    ChangeNetworkRootJob.perform_later(id)
  end

  def reindex_repository
    Search.add_to_search_index("repository", id)
  end

  def reindex_code
    if GitHub.use_elastomer_code_search?
      Search.add_to_search_index("code", id, "purge" => true)
    end
  end

  def reindex_commits
    Search.add_to_search_index("commit", id, "purge" => true)
  end

  def reindex_wiki
    Search.add_to_search_index("wiki", id, "purge" => true)
  end

  def reindex_issues(purge = false)
    Search.add_to_search_index("bulk_issues", id, "purge" => purge)
  end

  def reindex_discussions(purge = false)
    Search.add_to_search_index("bulk_discussions", id, "purge" => purge)
  end

  def reindex_pull_requests(purge = false)
    Search.add_to_search_index("bulk_pull_requests", id, "purge" => purge)
  end

  def reindex_projects(purge = false)
    Search.add_to_search_index("bulk_projects", id, "purge" => purge)
  end

  def reindex_releases(purge = false)
    Search.add_to_search_index("bulk_releases", id, "purge" => purge)
  end

  def reindex_dependabot_alerts(purge = false)
    Search.add_to_search_index("bulk_dependabot_alerts", id, "purge" => purge)
  end

  def purge_repository
    RemoveFromSearchIndexJob.set(queue: :index_low).perform_later("repository", id)
  end

  def purge_code
    return unless GitHub.use_elastomer_code_search?
    RemoveFromSearchIndexJob.set(queue: :index_low).perform_later("code", id)
  end

  def purge_commits
    RemoveFromSearchIndexJob.set(queue: :index_low).perform_later("commit", id)
  end

  def purge_wiki
    RemoveFromSearchIndexJob.set(queue: :index_low).perform_later("wiki", id)
  end

  def purge_issues
    RemoveFromSearchIndexJob.set(queue: :index_low).perform_later("bulk_issues", id)
  end

  def purge_pull_requests
    RemoveFromSearchIndexJob.set(queue: :index_low).perform_later("bulk_pull_requests", id)
  end

  def purge_projects
    RemoveFromSearchIndexJob.set(queue: :index_low).perform_later("bulk_projects", id)
  end

  def purge_discussions
    RemoveFromSearchIndexJob.set(queue: :index_low).perform_later("bulk_discussions", id)
  end

  def purge_releases
    RemoveFromSearchIndexJob.set(queue: :index_low).perform_now("bulk_releases", id)
  end

  def purge_dependabot_alerts
    RemoveFromSearchIndexJob.set(queue: :index_low).perform_later("bulk_dependabot_alerts", id)
  end

  def reindex_all
    reindex_repository
    reindex_code
    reindex_commits
    reindex_wiki
    reindex_issues(true)
    reindex_discussions(true)
    reindex_projects(true)
    reindex_pull_requests(true)
    reindex_releases(true)
    reindex_dependabot_alerts(true)
  end

  # Get a human-friendly description of the current file server offline status
  def fileserver_status
    begin
      num_routes = dgit_read_routes.size
    rescue GitHub::DGit::UnroutedError
      num_routes = 0
    end

    repo = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
      T.cast(Repositories.domain.by_id(id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    else
      Repository.find_by(id: id)
    end
    if num_routes >= repo&.dgit_copies
    # This repo is healthy
    elsif num_routes >= GitHub.dgit_quorum(repo&.dgit_copies)
      "Some Spokes replicas offline"
    elsif num_routes >= 1
      "Read-only, Spokes replicas offline"
    else
      "All Spokes replicas offline"
    end
  end

  def on_disk_status
    if !exists_on_disk?
      "Not on disk"
    elsif offline?
      "Repo offline"
    elsif access.broken?
      "Flagged as broken"
    elsif empty?
      if fork?
        "Forking in progress"
      elsif try(:mirror)
        "Mirroring in progress"
      else
        "Empty"
      end
    end
  end

  def disable_access(reason, disabling_user, **opts)
    DisableRepositoryAccessJob.perform_later(self, reason, disabling_user, **opts)
  end

  def enable_access(enabling_user)
    EnableRepositoryAccessJob.perform_later(self, enabling_user)
  end

  def disable_access_job_status
    DisableRepositoryAccessJob.status(repository)&.state
  end

  def enable_access_job_status
    EnableRepositoryAccessJob.status(repository)&.state
  end
end
