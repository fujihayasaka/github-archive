# typed: true
# frozen_string_literal: true

module Repository::ActivityDependency
  extend T::Helpers

  requires_ancestor { Repository }

  # Internal: Get the repository's three branches whose heads were most recently
  # touched by the specified user.
  #
  # user    - User object to find branches for
  # bad_oid - String target (commit) oid to ignore (optional)
  #
  # Returns an Array of Hashes with keys:
  #   :name - string of the branch's name
  #   :date - date of the last push
  def recently_touched_branches_for(user, bad_oid = nil)
    earliest_allowed_date = 1.hour.ago

    # Bail out early if there are no recently touched branches
    return [] if pushed_at < earliest_allowed_date

    # ignore the default and pages branches
    # and any branch that points to the default branch target
    bad_branches = [default_branch, pages_branch]
    bad_targets  = [default_oid, bad_oid].compact

    # Create hashes of branches from the push log
    # only care about the ones pushed by the current user
    # and were pushed less than an hour ago
    pushes = GitHub.dogstats.time("activity_dependency.recently_touched_branches_for.pushes_query") do
      with_database_error_fallback(fallback: []) do
        repositories_domain.pushes.latest_for(repository_id: T.must(self.id), pusher_id: user.id, pushed_at: earliest_allowed_date)
      end
    end

    user_branches = pushes.map do |push|
      name = push.ref.sub("refs/heads/", "")
      next if bad_branches.include?(name)
      next if bad_targets.include?(push.after)

      base_branch = base_branch(name, user)
      unless base_branch.frozen?
        base_branch = base_branch.force_encoding("utf-8").scrub
      end

      # ignore any branch that points to the same target as the parent branch
      # cf `#base_branch`, currently in refs_dependency.rb
      if (base = base_branch.split(":")[1])
        bad_target = T.cast(parent, Repository).heads.find(base).target_oid # rubocop:todo GitHub/AvoidCast
        next if bad_target == push.after
      end

      { name: name, date: push.pushed_at, commit_oid: push.after }
    end.compact

    # if the branch has been pushed multiple times in the last hour,
    # only show the most recent push
    user_branches.uniq! { |b| b[:name] }

    # only show branches that still exist
    user_branches.reject! { |b| b[:commit_oid] == GitHub::NULL_OID }

    # Cheap ahead-behind test: we only want to show branches that are
    # *ahead* of the main branch. Instead of doing a full ahead-behind
    # count, we see if our branch is reachable from the default branch.
    # If so, the branch is obviously *not* ahead.
    begin
      descendant_info = rpc.descendant_of(user_branches.collect { |b| [default_oid, b[:commit_oid]] })
      user_branches.reject! { |b| descendant_info[[default_oid, b[:commit_oid]]] }
    rescue GitRPC::SpawnFailure
      return []
    end

    return [] if user_branches.empty?

    # Find the pull requests for the remaining ones
    head_refs = user_branches.map { |b| b[:name] }
    pull_request_repository_ids = [id]

    # forked repo
    pull_request_repository_ids.push parent_id if fork?

    # advisory repo
    pull_request_repository_ids.push parent_advisory_repository.id if parent_advisory_repository.present? && (parent_advisory_repository.id != parent_id)

    matching_pull_requests = PullRequest.joins(:issue).where(
      base_repository_id: pull_request_repository_ids,
      head_ref: Git::Ref.permutations(head_refs)).where(
      [
        "(issues.state = ? OR
           (issues.state = ? AND issues.closed_at > ?)
         )",
         "open",
         "closed", earliest_allowed_date
      ],
    )

    pr_branches = Set.new(matching_pull_requests.collect(&:display_head_ref_name))

    # Filter out branches that have pull requests
    user_branches.reject! { |b| pr_branches.include?(b[:name]) }

    # Only the three most recent
    user_branches.first(3)
  end

  # Check to see if this repo has been pushed to. This means it fits into one of
  # three things:
  #
  #   * pushed_at is nil (the repo was never touched)
  #   * pushed_at is older than created_at (this is an untouched fork)
  #   * pushed_at == created_at, within 15 seconds
  #                  (the repo was only initialized on create and never touched)
  #
  # Returns a Boolean
  def never_pushed_to?
    pushed_at.nil? || pushed_at <= (T.must(created_at) + 15.seconds)
  end

  # Public: summarizes recent activity for this repository.
  #
  #
  # viewer  - User viewing the summary.
  # since   - When to summarize from. Absolute int unixtime.
  # period  - Alternative to since, specify a time period name like daily,
  #           halfweekly, weekly, or monthly
  # branch  - Branch to look at for commit summary.
  #
  # Returns an ActivitySummary object for the repository's recent activity.
  def activity_summary(options = {})
    if defined?(@activity_summary) && (options == @activity_summary_options)
      return @activity_summary
    end

    # Keep the options used to build the ActivitySummary cached so we can
    # invalidate if someone asks for an ActivitySummary with different options.
    @activity_summary_options = options
    @activity_summary = Repository::ActivitySummary.new(self, **options)
  end
end
