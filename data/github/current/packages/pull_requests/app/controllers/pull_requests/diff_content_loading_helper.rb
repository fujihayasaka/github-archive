# typed: true
# frozen_string_literal: true

module PullRequests::DiffContentLoadingHelper
  include GitHub::ResilienceMixin

  sig do
    params(
      pull: PullRequest,
      range: T.nilable(String),
      current_user: T.nilable(User),
      use_changes_range: T::Boolean,
      bypass_allowed_commits_validation: T::Boolean
    ).returns(T.nilable(PullRequest::Comparison))
  end
  def calculate_comparison(pull, range, current_user, use_changes_range = false, bypass_allowed_commits_validation: false)
    ENV["pull_request.timeout_reason"] = "compute_diff"

    if range
      start_commit_oid, end_commit_oid, used_base_keyword = parse_show_range_oid_components!(pull, range, bypass_allowed_commits_validation: bypass_allowed_commits_validation)

      expected_canonical_range = start_commit_oid ? "#{start_commit_oid}..#{end_commit_oid}" : "#{end_commit_oid}"
      # Don't redirect to canonical range when BASE keyword is used.
      # BASE is a semantic alias meaning "the correct base for this comparison", and the actual
      # SHA used may differ from base_sha (e.g., after merging main into the PR branch).
      # Keeping BASE in the URL avoids showing a potentially misleading SHA to users.
      if range != expected_canonical_range && !used_base_keyword
        Kernel.raise PullRequests::Errors::NonCanonicalRange.new(expected_canonical_range)
      end

      comparison = pull.historical_comparison
      merge_base_oid = comparison.compare_repository.best_merge_base(pull.base_sha, end_commit_oid)
      if merge_base_oid.nil?
        Kernel.raise PullRequests::Errors::OrphanCommit.new(end_commit_oid)
      end

      # When use_changes_range is true and we have a single OID (start_commit_oid is nil),
      # use the commit's parent as the start to show only that commit's changes
      if use_changes_range && start_commit_oid.nil? && !used_base_keyword
        commit = pull.compare_repository.commits.find(end_commit_oid)
        start_commit_oid = commit&.parent_oids&.first
      end

      # Fallback: if no valid start found, use merge base
      # This handles: BASE keyword, root commits, nil parents, and non-changes routes
      start_commit_oid ||= pull.compare_repository.best_merge_base(end_commit_oid, merge_base_oid)

      pull_comparison = PullRequest::Comparison.find(
        pull: pull,
        start_commit_oid: start_commit_oid,
        end_commit_oid: end_commit_oid,
        base_commit_oid: merge_base_oid,
        use_summary: true,
        viewer: current_user
      )
      Kernel.raise PullRequests::Errors::BadRange if pull_comparison.nil?
    else
      start_oid, end_oid = pull.merge_base, pull.head_sha
      Kernel.raise PullRequests::Errors::FilesUnavailable unless start_oid && end_oid

      start_commit, end_commit = pull.compare_repository.commits.find([start_oid, end_oid])
      pull_comparison = PullRequest::Comparison.new(
        pull: pull,
        start_commit: start_commit,
        end_commit: end_commit,
        base_commit: start_commit,
        use_summary: true,
        viewer: current_user
      )
    end

    ENV["pull_request.timeout_reason"] = nil
    pull_comparison
  end

  # Internal: Extract OID components from PR range.
  #
  #   /github/github/pull/123/files/abc123..def456
  #   /github/github/pull/123/files/def456
  #   /github/github/pull/123/files/BASE..def456
  #   /github/github/pull/123/files/abc123..HEAD
  #
  # pull  - Current PullRequest
  # range - String range parameter
  #
  # bypass_allowed_commits_validation - Boolean indicating whether to skip validation that commit is part of current PR.
  # Allows users to fetch more diffs in single file mode after a force push removes
  # a commit from the pull.
  #
  # If a complete range is given, a pair of resolved String OIDs will be
  # returned. If only one end sha is given, nil and a resolved String OID
  # will be returned. Otherwise nil is returned if no range was matched.
  #
  # Returns an array of [oid1, oid2, used_base_keyword] where used_base_keyword
  # indicates if the BASE keyword was used in the range.
  def parse_show_range_oid_components!(pull, range, bypass_allowed_commits_validation: false)
    used_base_keyword = false
    oids =
      if m = range.to_s.match(/\A(?<sha1>[a-fA-F0-9]{7,40}|BASE)\.\.(?<sha2>[a-fA-F0-9]{7,40}|HEAD)\z/i)
        sha1_is_base = m[:sha1].upcase == "BASE"
        sha2_is_head = m[:sha2].upcase == "HEAD"
        used_base_keyword = sha1_is_base

        # When BASE keyword is used, return nil for sha1 so callers use best_merge_base
        sha1 = sha1_is_base ? nil : m[:sha1]
        sha2 = sha2_is_head ? pull.head_sha : m[:sha2]

        # Only expand commit OIDs that aren't already resolved
        oids_to_expand = []
        oids_to_expand << sha1 unless sha1_is_base
        oids_to_expand << sha2 unless sha2_is_head

        if oids_to_expand.any?
          result = self.expand_commit_oids(pull.repository, oids_to_expand)
          sha1 = result[m[:sha1]] || sha1 unless sha1_is_base
          sha2 = result[m[:sha2]] || sha2 unless sha2_is_head
        end

        # sha1 can be nil when BASE keyword is used, but sha2 must be present
        [sha1, sha2] if sha2
      elsif m = range.to_s.match(/^(?<sha2>[a-fA-F0-9]{7,40})$/)
        result = self.expand_commit_oids(pull.repository, [m[:sha2]])
        sha2 = result[m[:sha2]]
        [nil, sha2] if sha2
      end

    Kernel.raise PullRequests::Errors::BadRange unless oids

    oid1, oid2 = oids

    if !bypass_allowed_commits_validation
      allowed_commits = pull.changed_commit_oids
      # oid1 is valid if: nil (single OID or BASE keyword) or in the changed commits
      oid1_valid = oid1.nil? || allowed_commits.include?(oid1)
      oid2_valid = allowed_commits.include?(oid2)

      unless oid1_valid && oid2_valid
        Kernel.raise PullRequests::Errors::BadRange
      end
    end

    # Skip descendant check when oid1 is nil because calculate_comparison will use best_merge_base instead
    if oid1
      if oid1 == oid2
        Kernel.raise PullRequests::Errors::BadRange
      end

      oid2_is_descendant_of_oid1 = pull.repository.rpc.descendant_of([[oid2, oid1]]).values.first
      unless oid2_is_descendant_of_oid1
        Kernel.raise PullRequests::Errors::BadRange
      end
    end

    [oid1, oid2, used_base_keyword]
  end

  def ignore_whitespace?(pull, params, current_user, logged_in)
    if %w[1 true].include? params[:w].to_s
      true
    elsif %w[0 false].include? params[:w].to_s
      false
    elsif logged_in
      with_database_error_fallback(fallback: false) { pull.ignore_whitespace?(current_user) }
    else
      false
    end
  end

  private def expand_commit_oids(repository, oids)
    oid_map = {}
    oids.each_slice(SpokesAPI::Client::RESOLVE_OBJECT_BATCH_SIZE).each do |batch|
      selectors = batch.map do |oid|
        {
          by_name: { name: oid },
          object_type: { type: :TYPE_COMMIT }
        }
      end

      objects = repository.spokes_api.resolve_objects_by(selectors)
      batch.zip(objects.items).each do |oid, resolved|
        # ensure resolved OID starts with the provided short OID (case insensitive),
        # to validate this is a commit reference & not a branch
        if resolved.error.empty? && resolved.object.oid.id.start_with?(oid.downcase)
          oid_map[oid] = resolved.object.oid.id
        end
      end
    end

    oid_map
  end
end
