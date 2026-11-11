# typed: strict
# frozen_string_literal: true

module AuthenticCommits
  module CommitContext
    # Public: Add a single new commit OID to the request context for tracking.
    # This method stores a single new commit oid that can be retrieved later
    # in the request lifecycle via pop_from_context.
    #
    # oid - String containing the commit OID to add to context.
    #
    # Returns nothing.
    sig do
      params(
        oid: String
      ).void
        .checked(:always)
        .on_failure(:raise)
    end
    def self.push_single(oid)
      if GitHub.context[:new_commits].present?
        commit_hash = GitHub.context.pop_key(:new_commits)
        return if commit_hash[:new_commits][oid].present?

        commit_hash[:new_commits][oid] = oid
        GitHub.context.push(commit_hash)
      else
        GitHub.context.push(new_commits: { oid => oid })
      end

      GitHub.logger.info "Added new single commit to context", "gh.commit.context.oid": oid
      GitHub.dogstats.increment("github.repositories.domain.commits.add_to_context", tags: ["type:single"])
    end

    # Public: Add a range of new commit OIDs to the request context for tracking.
    # This method stores a range of new commit oids that can be retrieved later
    # in the request lifecycle via pop_from_context.
    #
    # start_oid - String containing the starting commit OID of the range.
    # end_oid   - String containing the ending commit OID of the range.
    #
    # Returns nothing.
    # Raises StandardError if context already contains new commits.
    sig do
      params(
        start_oid: String,
        end_oid: String
      ).void
        .checked(:always)
        .on_failure(:raise)
    end
    def self.push_range(start_oid, end_oid)
      if GitHub.context[:new_commits].present?
        commit_hash = GitHub.context.pop_key(:new_commits)
        raise StandardError, "Context already has commits for this end_oid" if commit_hash[:new_commits][end_oid].present?

        commit_hash[:new_commits][end_oid] = start_oid
        GitHub.context.push(commit_hash)
      else
        # Note: this _backtracks_ because it's easier to lookup by the end_oid
        GitHub.context.push(new_commits: { end_oid => start_oid })
      end

      GitHub.logger.info "Added new commit range to context",
        "gh.commit.context.oid_start": start_oid,
        "gh.commit.context.oid_end": end_oid
      GitHub.dogstats.increment("github.repositories.domain.commits.add_to_context", tags: ["type:range"])
    end

    # Public: Retrieve and remove new commit information from the request context.
    # This method retrieves commit data that was previously stored using
    # push_to_context or push_range_to_context.
    #
    # Returns an Array containing [start_oid, end_oid].
    # For single commits, both values will be the same.
    # Returns [nil, nil] if no commits are found in context.
    sig { params(end_oid: String).returns([T.nilable(String), T.nilable(String)]) }
    def self.pop(end_oid)
      new_commits_hash = GitHub.context.pop_key(:new_commits)
      return [nil, nil] unless new_commits_hash

      new_commits = new_commits_hash[:new_commits]
      start_oid = new_commits.delete(end_oid)

      # push any remaining commits back to the stack
      GitHub.context.push(new_commits_hash) unless new_commits.empty?

      if start_oid.nil?
        GitHub.logger.error("Failed to retrieve new commits from context", "gh.commit.context.oid_end": end_oid)
        GitHub.dogstats.increment("github.repositories.domain.commits.get_from_context.error")
        return [nil, nil]
      end

      GitHub.logger.info "Retrieved new commits from context",
        "gh.commit.context.oid_start": start_oid,
        "gh.commit.context.oid_end": end_oid
      get_type = start_oid == end_oid ? "single" : "range"
      GitHub.dogstats.increment("github.repositories.domain.commits.get_from_context", tags: ["type:#{get_type}"])

      T.let([start_oid, end_oid], [T.nilable(String), T.nilable(String)])
    end

    # Public: Check if new commit information is currently stored in the request context.
    #
    # Returns true if there are new commits in the context,
    # returns false if there are not.
    sig { returns(T::Boolean) }
    def self.has_new_commits_in_context?
      GitHub.context[:new_commits].present?
    end
  end
end
