# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Return a summary log.
    #
    # since - limit to commits more recent than this date
    #
    # Returns an array of lines, or raises GitRPC::CommandFailed.
    def activity_summary_coauthors(since)
      send_message(:activity_summary_coauthors, since)
    rescue GitRPC::CommandFailed
      []
    end

    # Public: Return a shortlog with contributor info.
    #
    # oid - starting commit
    # ignore_merge_commits - true to not include merge commits in counts per email address
    #
    # Returns the shortlog as a string, or raises GitRPC::CommandFailed.
    def contributor_shortlog(oid, ignore_merge_commits: false)
      send_message(:contributor_shortlog, oid, ignore_merge_commits: ignore_merge_commits)
    end

    # Public: get the contribution counts for the authors in the ancestry of the given oid.
    #
    # oid - starting commit
    # ignore_merge_commits - true to not include merge commits in counts per email address
    # mailmap - true to respect mailmap configuration, otherwise that is ignored.
    #
    # Returns a map of <{ email: String , name: String } => contribution_count>
    def contributor_log(oid, ignore_merge_commits: false, mailmap: false)
      parts = ["contributor_log", oid]
      parts << "ignore_merge_commits" if ignore_merge_commits
      parts << "mailmap" if mailmap
      key = content_cache_key(*parts)

      cache_fetch(key, backend_method: :contributor_log) do
        send_message(:contributor_log, oid, ignore_merge_commits: ignore_merge_commits, mailmap: mailmap)
      end
    end

    # Public: Return author dates for commits.
    #
    # oid - starting commit
    #
    # Returns an array of RFC2822 author date strings, or raises GitRPC::CommandFailed.
    def repo_graph_log_times(oid)
      send_message(:repo_graph_log_times, oid)
    end

    # Public: Return commits with shortstat info.
    #
    # commitish - starting commit
    #
    # Returns an array of commit/shortstat pairs, or raises GitRPC::CommandFailed.
    def commit_stats_log(commitish)
      send_message(:commit_stats_log, commitish)
    end

    # Public: Return commits a page at a time, matching search criteria.
    #
    # commit_oid       - commit oid
    # path             - show only commits that touch this path
    # author_emails    - show only commits by authors matching this array of email addresses
    # committer_emails - show only commits by committers matching this array of email addresses
    # since_time       - show commits more recent than this date
    # until_time       - show commits older than this date
    # skip             - skip this many commits before starting output
    # max_count        - limit the number of commits to output
    #
    # Returns an array of commit oids, or raises GitRPC::CommandFailed.
    def paged_commits_log(commit_oid, options = {})
      # cache timeouts across forks etc. Since this just caches the timeout exception
      # it should be safe in the shared scope.
      timeout_key = content_cache_key("paged-commits-timeout", commit_oid, sha256(options.to_s), "v1")

      raise GitRPC::Timeout.new(cached: true) if cache.get(timeout_key)

      begin
        send_message(:paged_commits_log, commit_oid, **options)
      rescue GitRPC::Timeout => e
        cache.set(timeout_key, true, 300)
        raise e
      end
    end

    def async_paged_commits_log(commit_oid, options = {})
      # cache timeouts across forks etc. Since this just caches the timeout exception
      # it should be safe in the shared scope.
      timeout_key = content_cache_key("paged-commits-timeout", commit_oid, sha256(options.to_s), "v1")

      cache.async_get(timeout_key).then do |cached_timeout|
        raise GitRPC::Timeout.new(cached: true) if cached_timeout.exist?

        async_send_message(:paged_commits_log, commit_oid, **options).rescue do |e|
          case e
          when GitRPC::Timeout
            cache.async_set(timeout_key, true, 300)
          else
            raise e
          end
        end
      end
    end

    # Public: Return the last commit and its title.
    #
    # Returns a string or raises GitRPC::CommandFailed.
    def log_last_commit_oneline
      send_message(:log_last_commit_oneline)
    end
  end
end
