# typed: true
# frozen_string_literal: true

module Repository::SearchDependency
  extend T::Helpers

  requires_ancestor { Repository }

  # flag to skip the synchronize_search_index after_commit hook
  attr_accessor :skip_search_index_sync

  def skip_search_index_sync?
    !!skip_search_index_sync
  end

  # Public: Synchronize this repository with its representation in the search
  # index. If the repository is newly created or modified in some fashion,
  # then it will be updated in the search index. If the repository has been
  # destroyed, then it will be removed from the search index. This method
  # handles both cases.
  #
  # *args - Anything. Accepted so method can be used as an association callback.
  #
  # Returns this Repository instance.
  #
  def synchronize_search_index(*args)
    if self.destroyed? || !self.active?
      RemoveFromSearchIndexJob.perform_later("repository", self.id)
      RemoveFromSearchIndexJob.perform_later("bulk_issues", self.id)
      RemoveFromSearchIndexJob.perform_later("bulk_discussions", self.id)
      RemoveFromSearchIndexJob.perform_later("bulk_pull_requests", self.id)
      if GitHub.use_elastomer_code_search? && GitHub.code_search_indexing_enabled?
        RemoveFromSearchIndexJob.perform_later("code", self.id)
      end
      RemoveFromSearchIndexJob.perform_later("commit", self.id)
    elsif locked?
      # do nothing
    else
      if repo_is_searchable?
        Search.add_to_search_index("repository", self.id)
      else
        RemoveFromSearchIndexJob.perform_later("repository", self.id)
      end

      unless code_is_searchable?
        if GitHub.use_elastomer_code_search? && GitHub.code_search_indexing_enabled?
          RemoveFromSearchIndexJob.perform_later("code", self.id)
        end
      end

      unless commits_are_searchable?
        RemoveFromSearchIndexJob.perform_later("commit", self.id)
      end
    end

    self
  end

  # Public: If the `discussions.enabled` configuration setting has changed state, then we need to remove all discussions
  # for this repository from the search index or add them to the search index.
  #
  # *args - Anything. Accepted so method can be used as an association callback.
  #
  # Returns nothing.
  def synchronize_discussions_search_index(*args)
    if discussions_on?
      Search.add_to_search_index("bulk_discussions", id)
    else
      RemoveFromSearchIndexJob.perform_later("bulk_discussions", id)
    end
  end

  # If the `has_issues` flag has changed state, then we need to remove all
  # issues for this repository from the search index or add them to the search
  # index.
  #
  # *args - Anything. Accepted so method can be used as an association callback.
  #
  # Returns this Repository instance.
  #
  # TODO combine the two synchronize index methods into one and use Foca's
  # code from PR 8480
  #
  def synchronize_issues_search_index(*args)
    return self unless previous_changes.key?("has_issues")

    if self.has_issues
      Search.add_to_search_index("bulk_issues", self.id)
    else
      RemoveFromSearchIndexJob.perform_later("bulk_issues", self.id)
    end

    self
  end

  # If repo contains action, then we need to update the RepositoryAction Index
  # currently the stars count is updated only when new version of action is released
  # this shows a inconsitent count of stars in the marketplace search results and details page
  def synchronize_repository_actions_search_index(*args)
    return self unless listed_action

    Search.add_to_search_index("repository_action", listed_action&.id)
  end

  # Should we be adding this repository to the search index? Reasons for
  # keeping it out of the search index are:
  #   - Not routed on the file servers
  #   - The user is a spammer or doesn't exist
  #   - Disabled by an admin
  #
  # Return `true` if we should add the repository to the search index; return
  # `false` if we should not.
  #
  def repo_is_searchable?(log_reason: false)
    unless active?
      GitHub.dogstats.increment("repo.is_searchable", tags: ["value:false", "reason:!active"]) if log_reason
      return false
    end
    # When the repo does not belong to a valid network (usually means in the
    # process of deleting or restoring).
    if network.nil?
      GitHub.dogstats.increment("repo.is_searchable", tags: ["value:false", "reason:network.nil"]) if log_reason
      return false
    end
    # When the .git repo is un-routed on the file servers
    unless routed?
      GitHub.dogstats.increment("repo.is_searchable", tags: ["value:false", "reason:not_routed"]) if log_reason
      return false
    end
    # When user is nil don't index it
    if user.nil?
      GitHub.dogstats.increment("repo.is_searchable", tags: ["value:false", "reason:user_nil"]) if log_reason
      return false
    end
    # When the repo or the user is spammy
    if spammy? || owner&.spammy?
      GitHub.dogstats.increment("repo.is_searchable", tags: ["value:false", "reason:spammy"]) if log_reason
      return false
    end
    # When the repo has been disabled for any reason
    if !disabled_at.nil?
      GitHub.dogstats.increment("repo.is_searchable", tags: ["value:false", "reason:disabled"]) if log_reason
      return false
    end
    # When the repository network is broken
    if network&.broken?
      GitHub.dogstats.increment("repo.is_searchable", tags: ["value:false", "reason:network_broken"]) if log_reason
      return false
    end
    # The repo is safe to index
    true

  # Since rpc is memoized, rpc.online? can return true for just-deleted
  # repos, and then we get an UnroutedError when we call route.  Catch
  # that exception and don't log it.
  rescue GitHub::DGit::UnroutedError
    GitHub.dogstats.increment("repo.is_searchable", tags: ["value:false", "reason:unrouted_error"]) if log_reason
    false
  rescue StandardError => boom # rubocop:todo Lint/RescueException
    GitHub.dogstats.increment("repo.is_searchable", tags: ["value:false", "reason:standard_error"]) if log_reason
    report_error boom
    false
  end

  # Should we be adding the source code for this repository to the search
  # index? Reasons for keeping it out of the search index are:
  #   - The repository is not searchable
  #   - No content in the git repo
  #   - Fork with no unique commits
  #   - Fork with fewer watchers than the parent
  #
  # Return `true` if we should add the source code to the search index; return
  # `false` if we should not.
  #
  def code_is_searchable?(log_reason: false)
    return false unless repo_is_searchable?
    # Definitely hide if this repo is empty.
    return false if empty?
    # Code search has been specifically enabled for a fork
    return true if code_search_enabled
    # Also hide forks with no unique code or no significant popularity
    if fork? && !popular_fork?
      GitHub.dogstats.increment("repo.code_is_searchable", tags: ["value:false", "reason:fork"]) if log_reason
      GitHub.logger.info("code is searchable", {
        "value" => false,
        "reason" => "fork",
        "repo_id" => self.id,
        "nwo" => self.name_with_display_owner,
      }) if log_reason
      return false
    end
    # If we got this far, then add to the search index
    true

  # Code is not searchable if we don't have a route to the repo
  rescue GitHub::DGit::UnroutedError
    false
  end

  # Public: Status of this repository in the Blackbird search clusters.
  # NOTE: You must call `prefill_blackbird_code_search_status` to set this field.
  attr_accessor :blackbird_code_search_status

  # Public: Prefill the Blackbird code search index status for an array of repositories.
  def self.prefill_blackbird_code_search_status(repositories)
    # NB: Set a conservative batch size. The GetRepositoryStatus endpoint takes at most 1000 repos ids.
    repositories.each_slice(100) do |repos_batch|
      resp = BlackbirdSearch::Client.get_repository_status(repos_batch.map(&:id))
      if resp.error
        err = T.must(resp.error)
        GitHub.logger.error("blackbird get_repository_status failed", "blackbird.error.code": err.code, "blackbird.error.msg": err.msg)
        return false
      end
      repos_batch.zip(resp.data.repositories).each do |repo, repo_status|
        repo.blackbird_code_search_status = repo_status
      end
    end
    true
  rescue ::Faraday::Error => e
    GitHub.logger.error("blackbird get_repository_status failed", {
      :exception => e,
      "code.namespace" => self.name,
      "code.function" => __method__
      })
    false
  end

  # Should we be adding the commits for this repository to the search
  # index?
  #
  # Return `true` if we should add the commits to the search index; return
  # `false` if we should not.
  #
  def commits_are_searchable?
    return false unless repo_is_searchable?
    # Definitely hide if this repo is empty.
    return false if empty?
    # Also hide forks with no unique code or no significant popularity
    return false if fork? && !popular_fork?
    # If we got this far, then add to the search index
    true

  # Commits are not searchable if we don't have a route to the repo
  rescue GitHub::DGit::UnroutedError
    false
  end

  # Fetch the search result for this Repository.
  #
  # Returns a Hash of repo details.
  def search_entry
    index = Elastomer::Indexes::Repos.new
    result = index.docs.get type: "repository", id: self.id
    result["found"] ? result["_source"] : {}
  end

  # Public: Returns an elasticsearch query string that will find all of this
  # repo's audit log events
  #
  # Returns a String which can be passed to elasticsearch as a `query_string`
  def audit_log_query
    "repo_id:#{id}"
  end

  def audit_log_kql_query
    "webevents | where repo_id == #{id}"
  end
end
