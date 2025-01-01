# typed: true
# frozen_string_literal: true

module PullRequests::DiffContentLoadingHelper
  include GitHub::ResilienceMixin

  sig do
    params(
      pull: PullRequest,
      range: T.nilable(String),
      current_user: T.nilable(User)
    ).returns(T.nilable(PullRequest::Comparison))
  end
  def calculate_comparison(pull, range, current_user)
    ENV["pull_request.timeout_reason"] = "compute_diff"

    if range
      start_commit_oid, end_commit_oid = parse_show_range_oid_components!(pull, range)

      expected_canonical_range = start_commit_oid ? "#{start_commit_oid}..#{end_commit_oid}" : "#{end_commit_oid}"
      if range != expected_canonical_range
        Kernel.raise PullRequestsController::NonCanonicalRange.new(expected_canonical_range)
      end

      comparison = pull.historical_comparison
      merge_base_oid = comparison.compare_repository.best_merge_base(pull.base_sha, end_commit_oid)
      if merge_base_oid.nil?
        Kernel.raise PullRequestsController::OrphanCommit.new(end_commit_oid)
      end

      start_commit_oid ||= pull.compare_repository.best_merge_base(end_commit_oid, merge_base_oid)

      pull_comparison = PullRequest::Comparison.find(
        pull: pull,
        start_commit_oid: start_commit_oid,
        end_commit_oid: end_commit_oid,
        base_commit_oid: merge_base_oid,
        use_summary: true,
        viewer: current_user
      )
      Kernel.raise PullRequestsController::BadRange if pull_comparison.nil?
    else
      start_oid, end_oid = pull.merge_base, pull.head_sha
      Kernel.raise PullRequestsController::FilesUnavailable unless start_oid && end_oid

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
  #
  # pull  - Current PullRequest
  # range - String range parameter
  #
  # If a complete range is given, a pair of resolved String OIDs will be
  # returned. If only one end sha is given, nil and a resolved String OID
  # will be returned. Otherwise nil is returned if no range was matched.
  def parse_show_range_oid_components!(pull, range)
    oids =
      if m = range.to_s.match(/\A(?<sha1>[a-fA-F0-9]{7,40})\.\.(?<sha2>[a-fA-F0-9]{7,40}|HEAD)\z/)
        sha2 = m[:sha2] == "HEAD" ? pull.head_sha : m[:sha2]
        result = pull.repository.expand_oids([m[:sha1], sha2], "commit")
        sha1, sha2 = result[m[:sha1]], result[sha2]
        [sha1, sha2] if sha1 && sha2
      elsif m = range.to_s.match(/^(?<sha2>[a-fA-F0-9]{7,40})$/)
        result = pull.repository.expand_oids([m[:sha2]], "commit")
        sha2 = result[m[:sha2]]
        [nil, sha2] if sha2
      end

    Kernel.raise PullRequestsController::BadRange unless oids

    oid1, oid2 = oids

    allowed_commits = pull.changed_commit_oids
    if !(oid1.nil? || allowed_commits.include?(oid1)) || !allowed_commits.include?(oid2)
      Kernel.raise PullRequestsController::BadRange
    end

    if oid1 && (oid1 == oid2 || !pull.repository.rpc.descendant_of([[oid2, oid1]]).values.first)
      Kernel.raise PullRequestsController::BadRange
    end

    oids
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
end
