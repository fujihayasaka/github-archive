# typed: true
# frozen_string_literal: true

module PullRequest::ReviewsDependency
  extend T::Helpers

  requires_ancestor { PullRequest }

  BEST_MERGE_BASE_TIMEOUT_SECONDS = 15

  def build_code_scanning_variant_review(&block)
    build_variant_review(:code_scanning, &block)
  end

  def build_dependabot_variant_review(&block)
    build_variant_review(:dependabot, &block)
  end

  def build_variant_review(variant, &block)
    review = reviews.build(
      variant_type: PullRequestReview.variant_types[variant],
      head_sha: head_sha,
      merge_base_sha: find_best_merge_base_sha
    )
    block.call(review) if block
    review
  end

  def latest_reviews_for(viewer)
    reviews.for_viewer(viewer).filter_spam_for(viewer).order(:submitted_at, :created_at)
  end

  def reviews_for(viewer)
    @reviews_for ||= Hash.new do |h, k|
      h[k] = reviews.for_viewer(k).filter_spam_for(k).includes(:user).to_a
    end
    @reviews_for[viewer]
  end

  # When creating a new review we skip touching the pull request. This is done to ensure we don't
  # trigger UI updates on the pull request before we are able to modify the newly created pending review.
  sig { params(user: User, head_sha: T.nilable(String)).returns(PullRequestReview) }
  def pending_review_for(user:, head_sha: nil)
    head_sha = self.head_sha if head_sha.blank?
    merge_base_sha = find_best_merge_base_sha
    existing_review = reviews.with_pending_state.where(user_id: user.id).first
    existing_review || PullRequest.no_touching { reviews.with_pending_state.create(user_id: user.id, head_sha: head_sha, merge_base_sha: merge_base_sha) }
  end

  def async_status_at_merge
    return @async_status_at_merge if defined?(@async_status_at_merge)

    @async_status_at_merge = begin
      return Promise.resolve(nil) unless merged?

      async_repository.then do |repo|
        commit_statuses = Statuses::Service.statuses_at_merge(repository: repository, sha: head_sha, merged_at: merged_at)
        check_runs = CheckRun.check_runs_at_merge(repository: repository, sha: head_sha, merged_at: merged_at)
        if commit_statuses.any? || check_runs.any?
          ::CombinedStatus.new(repo, head_sha, statuses: commit_statuses, check_runs: check_runs)
        end
      end
    end
  end

  def async_pending_review_by?(user)
    return Promise.resolve(false) unless user

    Platform::Loaders::PendingPullRequestReviewCheck.load(id, user.id)
  end

  def pending_review_by?(user)
    latest_pending_review_for(user).present?
  end

  def latest_pending_review_for(user)
    @latest_pending_review_for ||= Hash.new do |h, k|
      h[k] = reviews.where(
               user_id: k.id,
               state: PullRequestReview.state_value(:pending),
             ).first
    end
    @latest_pending_review_for[user]
  end

  def async_latest_non_pending_review_for(user)
    Platform::Loaders::LatestNonPendingPullRequestReview.load(id, user.id)
  end

  def revision_marker(user)
    PullRequestRevisionMarker.latest_for(self, user)
  end

  def latest_non_pending_review_for(user)
    async_latest_non_pending_review_for(user).sync
  end

  def latest_enforced_review_for(user)
    return unless user

    reviews = latest_enforced_reviews(writers_only: false).select do |review|
      review.user_id == user.id
    end

    reviews.max_by(&:created_at)
  end

  def stale_file_reviews(before:, after:)
    return [] unless open?
    return [] unless user_reviewed_files.not_dismissed.any?
    return [] unless current_comparison = current_pull_comparison(before: before, after: after)

    changed_paths = current_comparison.diffs.summary.deltas.map(&:path).uniq
    all_paths = changed_paths_for_codeowners
    return [] if codeowners_paths_load_error?

    stale_file_reviews = []

    user_reviewed_files.not_dismissed.group_by(&:filepath).each do |path, reviewed_files|
      if changed_paths.include?(path) || !all_paths.include?(path)
        T.unsafe(stale_file_reviews).push(*reviewed_files)
      end
    end

    stale_file_reviews
  end

  # The list of reviewed and dismissed files for a given user
  def user_reviewed_files_for(user)
    @user_reviewed_files_for ||= Hash.new do |h, user|
      h[user] = PullRequestUserReviews.new(self, user)
    end[user]
  end

  # Public: Return the commit OIDs / head SHAs for any commit the user
  #         submitted a review on for the given pull request.
  #
  # user - The user who submitted reviews.
  # candidate_oids - Optional. If present, limits the returned OIDs to be
  #                  from the given list of OIDs.
  #
  # Returns and Array of OID strings.
  def reviewed_commit_oids(user:, candidate_oids: nil, limit: 200)
    return [] unless user
    return [] if candidate_oids&.empty?
    arel = reviews.submitted.
      where(user_id: user.id).
      select("DISTINCT head_sha").
      limit(limit)
    arel = arel.where(head_sha: candidate_oids) if candidate_oids&.any?
    arel.pluck(:head_sha)
  end

  # Public: Returns a list of the most recent review that each user has left,
  # as long as the review's status is approved or rejected.
  #
  # Includes dismissed in the query so that we can filter those out after.
  # This is so that we consider a most recent review which is dismissed
  # to be essentially ignored in the merge area.
  #
  # writers_only - Boolean indicating whether only consider reviews of users with
  #                write access to the pull request's base repository
  #
  # Returns Array of PullRequestReviews
  def latest_enforced_reviews(writers_only:)
    async_latest_enforced_reviews(writers_only: writers_only).sync
  end

  # Public: Returns a promise resolving to a list of the most recent review that each user has left,
  # as long as the review's status is approved or rejected.
  #
  # Includes dismissed in the query so that we can filter those out after.
  # This is so that we consider a most recent review which is dismissed
  # to be essentially ignored in the merge area.
  #
  # writers_only - Boolean indicating whether only consider reviews of users with
  #                write access to the pull request's base repository
  #
  # Returns the promise which would resolve to an Array of PullRequestReviews
  def async_latest_enforced_reviews(writers_only:)
    return Promise.resolve(@latest_enforced_reviews[writers_only]) if @latest_enforced_reviews&.key? writers_only

    @latest_enforced_reviews ||= {}

    Platform::Loaders::PullRequestEnforcedReviews
      .load(self, writers_only: writers_only)
      .then { |value| @latest_enforced_reviews[writers_only] = value }
  end

  def async_latest_enforced_reviews_candidate(writers_only:)
    return Promise.resolve(@latest_enforced_reviews_candidate[writers_only]) if @latest_enforced_reviews_candidate&.key? writers_only

    @latest_enforced_reviews_candidate ||= {}

    Platform::Loaders::PullRequestEnforcedReviewsCandidate
      .load(self, writers_only: writers_only)
      .then { |value| @latest_enforced_reviews_candidate[writers_only] = value }
  end

  def latest_enforced_reviews_count_for(review_state)
    latest_enforced_reviews(writers_only: true).count do |review|
      review.state == PullRequestReview.state_value(review_state)
    end
  end

  # Works the same as async_latest_enforced_reviews(), but also preloads some associations on the reviews and
  # on this pull request. Calls async_latest_enforced_reviews, so it shares the same result cache.
  #
  # This is a drop-in replacement for async_latest_enforced_reviews. It will be slower since it's bringing in
  # more from the database, but much faster than lazy-loading, especially in the case where you have multiple PR's.
  def async_latest_enforced_reviews_with_prefetch(writers_only:)
    async_latest_reviews = async_latest_enforced_reviews(writers_only:)

    if @prefetched_latest_review_associations&.[](writers_only)
      # Related associations have already been loaded for this cached result set.
      return async_latest_reviews
    end
    @prefetched_latest_review_associations ||= {}
    @prefetched_latest_review_associations[writers_only] = true

    # To prevent an N+1 cascade when GraphQL loads many PR's at once, we need to preload some associations:
    #   0: pull_request.reviews -- already loaded by async_latest_enforced_reviews() above
    #   1: pull_request.review_requests         × count(review_requests)
    #   2: latest_reviews.user                  × count(latest_reviews)
    #   3: review_requests.reviewer             × count(review_requests)
    #   4: review_requests.pull_request_reviews × count(review_requests) × has_many
    # See https://github.com/github/repos/issues/5982

    Promise.all([
      async_latest_reviews,                       # 0
      async_review_requests,                      # 1
    ]).then do |(latest_reviews, review_requests)|
      Promise.all([
        latest_reviews.map(&:async_user),         # 2
        review_requests
          .map do |request|
            [
              request.async_reviewer,             # 3
              request.async_pull_request_reviews, # 4
            ]
          end,
      ].flatten)
      .then { latest_reviews }
    end
  end

  # Public: Return the latest reviews for the pull request by user,
  # preferring opinionated reviews over commenting reviews
  # e.g. If a user left an approval, then commented, return the approval
  # e.g. If a user left an approval, then commented, then the approval was dismissed, return the most recent review
  #
  # Returns a promise that resolves to an Array of PullRequestReviews
  sig { params(user: T.nilable(User)).returns(Promise[T::Array[PullRequestReview]]) }
  def async_latest_reviews_preferring_opinionated_reviews(user)
    async_latest_enforced_reviews(writers_only: false).then do |enforced_reviews|
      visible_reviews = visible_sidebar_reviews(user)

      latest_review_by_author = visible_reviews.index_by(&:user_id)
      latest_enforced_review_by_author = enforced_reviews.index_by(&:user_id)

      latest_review_by_author.map do |user_id, review|
        if review.commented?
          latest_enforced_review_by_author[user_id] || review
        else
          review
        end
      end
    end
  end

  # Public: Return the status of each enforced review on this pull request.
  #
  # Returns a Hash[PullRequestReview => status], where the status is one of:
  # :current                   - Review is current
  # :stale_head_changed        - Review is stale because the head of the pull request source branch changed
  # :stale_merge_base_changed  - Review is stale because the merge base of the pull request changed
  sig do params(
    head_sha: T.nilable(String),
    base_sha: T.nilable(String),
    use_current_base_sha: T::Boolean)
    .returns(T::Hash[PullRequestReview, Symbol])
  end
  def compute_review_statuses(head_sha: nil, base_sha: nil, use_current_base_sha: false)
    async_compute_review_statuses(head_sha:, base_sha:, use_current_base_sha:).sync
  end

  # Public: Return the status of each enforced review on this pull request.
  #
  # Returns a Promise[Hash[PullRequestReview => status]], where the status is one of:
  # :current                   - Review is current
  # :stale_head_changed        - Review is stale because the head of the pull request source branch changed
  # :stale_merge_base_changed  - Review is stale because the merge base of the pull request changed
  sig do params(
    head_sha: T.nilable(String),
    base_sha: T.nilable(String),
    use_current_base_sha: T::Boolean)
    .returns(Promise[T::Hash[PullRequestReview, Symbol]])
  end
  def async_compute_review_statuses(head_sha: nil, base_sha: nil, use_current_base_sha: false)
    head_sha = T.let(head_sha, T.nilable(String))
    Promise.all([
      async_head_repository,
      async_latest_enforced_reviews(writers_only: true)
    ]).then do |head_repository, reviews|
      GitHub.dogstats.time("PullRequest.compute_review_statuses", tags: ["reviews:#{reviews.length}"]) do
        result = T.let(Hash.new, T::Hash[PullRequestReview, Symbol])
        best_merge_base_sha = T.let(nil, T.nilable(String))

        if reviews.none?(&:approved?)
          # Short-circuit if there are no approved reviews
          result = Hash[reviews.map { |r| [r, :current] }]
        else
          if !head_repository
            result = Hash[reviews.map { |r| [r, :stale_head_changed] }]
          else
            head_sha ||= self.head_sha

            best_merge_base_sha = find_best_merge_base_sha(head_sha:, base_sha:, use_current_base_sha:)
            if !best_merge_base_sha
              result = Hash[reviews.map { |r| [r, :stale_merge_changed] }]
            else
              begin
                commits_to_find = [best_merge_base_sha, head_sha]
                commits_to_find.concat(
                  reviews
                    .select { |r| r.approved? }
                    .flat_map { |r| [r.head_sha, r.merge_base_sha] }
                    .uniq.compact)

                # This loads all the interesting commits into GitRPC::Client.@cache in one shot
                best_merge_base_commit, head_commit = head_repository.commits.find(commits_to_find)

              rescue GitRPC::Timeout, GitRPC::ObjectMissing, GitRPC::InvalidObject, RepositoryObjectsCollection::InvalidObjectId => e
                # Something went wrong, so we'll just assume all the reviews are stale.
                base_repository = T.must(self.base_repository)

                GitHub.logger.info(
                  "compute_review_statuses: problem",
                  "exception.type": e.class.name,
                  "exception.message": e.message,
                  "gh.pull_request.head_sha": head_sha,
                  "gh.pull_request.base_sha": base_sha,
                  "gh.pull_request.base_ref": base_ref,
                  "gh.pull_request.head_ref": base_ref,
                  "gh.pull_request.id": self.id,
                  "gh.pull_request.base_repo.id": base_repository.id,
                  "gh.pull_request.base_repo.owner_id": base_repository.owner&.id,
                  "gh.pull_request.head_repo.id": head_repository.id,
                  "gh.pull_request.head_repo.owner_id": head_repository.owner&.id
                )
                result = Hash[reviews.map { |r| [r, :stale_head_changed] }]

              else
                reviews.each do |review|
                  if !review.approved?
                    # Only approvals are dismissed or get stale
                    result[review] = :current
                    next
                  end

                  review_head_commit, review_merge_base_commit = head_repository.commits.find([review.head_sha, review.merge_base_sha].compact)

                  case
                  when review_head_commit.tree_oid != head_commit.tree_oid
                    result[review] = :stale_head_changed
                  when review_merge_base_commit.nil?
                    # In the future, only very old review records will have no merge_base_sha. At some point we might start
                    # treating "nil merge base" as :stale_merge_changed. For now we'll treat it as current if head is current.
                    result[review] = :current
                  when review_merge_base_commit.tree_oid != best_merge_base_commit.tree_oid
                    result[review] = :stale_merge_changed
                  else
                    result[review] = :current
                  end
                end
              end
            end
          end
        end

        result
      end # dogstats.time
    end # Promise.then
  end

  # Public - Returns the best merge base sha for this pull request.
  #
  # use_current_base_sha - If true, the current head commit of the base target branch will be used instead of the
  # base_sha stored in the database.
  #
  # Returns oid as a String or nil.
  sig do params(
    head_sha: T.nilable(String),
    base_sha: T.nilable(String),
    use_current_base_sha: T::Boolean)
    .returns(T.nilable(String))
  end
  def find_best_merge_base_sha(head_sha: nil, base_sha: nil, use_current_base_sha: false)
    async_find_best_merge_base_sha(head_sha:, base_sha:, use_current_base_sha:).sync
  end

  # Public - Returns the best merge base sha for this pull request.
  #
  # use_current_base_sha - If true, the current head commit of the base target branch will be used instead of the
  # base_sha stored in the database.
  #
  # Returns oid as a Promise[String or nil].
  sig do params(
    head_sha: T.nilable(String),
    base_sha: T.nilable(String),
    use_current_base_sha: T::Boolean)
    .returns(Promise[T.nilable(String)])
  end
  def async_find_best_merge_base_sha(head_sha: nil, base_sha: nil, use_current_base_sha: false)
    head_sha = T.let(head_sha, T.nilable(String))
    base_sha = T.let(base_sha, T.nilable(String))

    async_head_repository.then do |head_repository|
      if !head_repository
        Promise.resolve(nil)
      else
        GitHub.dogstats.time("PullRequest.find_best_merge_base_sha", tags: ["use_current_base_sha:#{!!use_current_base_sha}"]) do
          head_sha ||= self.head_sha
          base_sha ||= use_current_base_sha ? current_base_sha : self.base_sha

          merge_base_sha = T.let(nil, T.nilable(String))
          error = T.let(nil, T.nilable(StandardError))

          if head_sha && base_sha
            begin
              if head_repository.id != T.must(base_repository).id
                head_repository.fetch_commits_from_network(base_repository, base_sha)
              end

              head_repository.rpc.with_timeout(BEST_MERGE_BASE_TIMEOUT_SECONDS) do
                merge_base_sha = head_repository.rpc.best_merge_base(base_sha, head_sha)
              end
            rescue GitRPC::Timeout, GitRPC::ObjectMissing, GitRPC::InvalidObject, RepositoryObjectsCollection::InvalidObjectId => e
              error = e
            end
          end

          if !merge_base_sha
            repository = T.must(self.repository)
            GitHub.dogstats.increment("pull_request.find_best_merge_base_sha.failure", tags: ["use_current_base_sha:#{!!use_current_base_sha}"])
            GitHub.logger.info(
              "find_best_merge_base_sha: no result",
              "exception.type": error&.class&.name,
              "exception.message": error&.message,
              "gh.pull_request.head_sha": head_sha,
              "gh.pull_request.base_sha": base_sha,
              "gh.pull_request.base_ref": base_ref,
              "gh.pull_request.id": self.id,
              "gh.repo.id": repository.id,
              "gh.owner.id": repository.owner&.id
            )
          end

          merge_base_sha
        end # dogstats.time
      end
    end # Promise.then
  end

  # This is a more-general approach to promoting reviews. Instead of only promoting approvals from
  # one specific commit id to another, it attempts to promote all approvals which are behind the source HEAD.
  sig { params(new_head_sha: T.nilable(String)).void }
  def promote_reviews_to_latest_head(new_head_sha = nil)
    return unless head_repository

    new_head_sha ||= head_sha
    return unless new_head_sha

    # Only approvals need to be promoted, since only approvals are in danger of dismissal
    approvals = reviews.filter(&:approved?)
    return if approvals.empty?

    error = T.let(nil, T.nilable(StandardError))
    updated_count = T.let(0, Integer)

    GitHub.dogstats.time("pullrequest.promote_reviews_to_latest_head") do
      begin
        head_repository = T.must(self.head_repository)

        if base_repository && head_repository.id != T.must(base_repository).id
          head_repository.fetch_commits_from_network(base_repository, current_base_sha)
        end

        # Find head_shas of all approvals which are behind the current HEAD
        old_head_shas = approvals.map { |r| r.head_sha }.compact.uniq
        old_head_shas.delete(new_head_sha)

        # Find merge base sha for all out-of-date head shas
        old_merge_base_shas = old_head_shas.each_with_object({}) do |old_head_sha, h|
          h[old_head_sha] = head_repository.rpc.best_merge_base(current_base_sha, old_head_sha)
        end

        # Find merge base between current base branch and head branch
        new_merge_base_sha = head_repository.rpc.best_merge_base(current_base_sha, new_head_sha)

        # This loads all the interesting commits into GitRPC::Client.@cache in one shot
        commits_to_find = [
          old_head_shas, old_merge_base_shas.values, new_head_sha, new_merge_base_sha,
          approvals.map { |r| r.merge_base_sha }
        ].flatten.compact.uniq
        head_repository.commits.find(commits_to_find)

        new_head_commit = head_repository.commits.find(new_head_sha)
        break unless new_head_commit

        # For each out-of-date head_sha, create a trusted merge and see if reviews can be promoted
        old_head_shas.each do |old_head_sha|
          old_merge_base_sha = old_merge_base_shas[old_head_sha]
          next unless old_merge_base_sha
          old_merge_base_commit = head_repository.commits.find(old_merge_base_sha)
          next unless old_merge_base_commit

          # Create a merge between old head commit and new merge base to see if
          # 1. merge is clean, and 2. it is tree-same to user-created commit
          trusted_merge_commit = head_repository.commits.create_merge_commit(
            safe_user,
            new_merge_base_sha,
            old_head_sha
          ).first
          next unless trusted_merge_commit

          # Check that updates to the head branch updates haven't introduced new changes
          next unless new_head_commit.tree_oid == trusted_merge_commit.tree_oid

          approvals.filter { |r| r.head_sha == old_head_sha }.to_a.each do |review|
            # If review merge base is set, check that it is still valid
            if review.merge_base_sha
              review_merge_base_commit = head_repository.commits.find(review.merge_base_sha)
              next unless old_merge_base_commit.tree_oid == review_merge_base_commit.tree_oid
            end

            review.head_sha = new_head_sha
            review.merge_base_sha = new_merge_base_sha
            ActiveRecord::Base.connected_to(role: :writing) do
              review.save!
            end
            updated_count += 1
          end
        end
      rescue GitRPC::Timeout, GitRPC::ObjectMissing, GitRPC::InvalidObject, RepositoryObjectsCollection::InvalidObjectId => e
        error = e
      end
    end

    reset_latest_enforced_reviews_cache

    GitHub.logger.info("pull_request.promote_reviews_to_latest_head", {
      base_ref: base_ref,
      head_ref: head_ref,
      pull_request_id: self.id,
      pull_request_number: self.number,
      repo_id: repository.try(:id),
      repo_name: repository.try(:name),
      owner_id: repository.try(:owner).try(:id),
      owner_login: repository.try(:owner).try(:display_login),
      business_id: repository.try(:owner).try(:business).try(:id),
      business_slug: repository.try(:owner).try(:business).try(:slug),
      review_count: reviews.count,
      updated_count: updated_count,
      exception_type: error.try(:class).try(:name),
      exception_message: error.try(:message),
      new_head_sha: new_head_sha,
    })
  end

  # Public: Does the pull request allow non-comment reviews (e.g. approval or request changes)
  # from the reviewer?
  #
  # reviewer - The User reviewing the pull request.
  #
  # Returns a Boolean.
  def allows_non_comment_reviews_from?(reviewer:)
    return false if reviewer == user

    return true unless GitHub.code_review_limits_enabled?

    if (repo = repository) && repo.non_comment_pull_request_reviews_restricted?
      if reviewer.bot?
        reviewer.associated_repository_ids(
          min_action: :read,
          resource: "pull_requests",
          repository_ids: [repo.id]
        ).any?
      else
        repo.async_has_access?(reviewer).sync
      end
    else
      true
    end
  end

  # This is used for indexing in search
  #
  # Returns Strings describing the current state of the review policy in the merge box
  def review_merge_states(viewer: nil)
    policy_decision = cached_merge_state(viewer: viewer).pull_request_review_policy_decision
    states = []

    if policy_decision.changes_requested?
      states << "changes_requested"
    elsif policy_decision.approved?
      states << "approved"
    else
      states << "required" if policy_decision.more_reviews_required?
      states << "none" unless policy_decision.has_reviews?
    end

    states
  end

  # Internal: Dismisses any currently approved reviews which no longer include the
  # latest changes.
  #
  # actor                 - The User who performed the push or merge which triggered the dismissal.
  # changing_base         - True if the base_ref of this pull request is being changed.
  # base_changed_manually - True if the base_ref is changing because user manually retargeted the PR.
  #                         This can be removed once all repos are using strict reivews.
  #
  # Returns nothing.
  def dismiss_stale_reviews(actor:, changing_base:, base_changed_manually:)
    dismiss_stale_reviews_strict(actor:, changing_base:, base_changed_manually:)
  end

  sig { params(actor: User, changing_base: T::Boolean, base_changed_manually: T::Boolean).void }
  def dismiss_stale_reviews_strict(actor:, changing_base:, base_changed_manually:)
    compute_review_statuses(use_current_base_sha: true).each do |review, status|
      reason = case
      when !review.approved?
        # Only approvals are ever dismissed
        nil
      when changing_base
        GitHub.dogstats.increment("PullRequest.dismiss_stale_reviews", tags: ["reason:changing_base"])
        { message: "The base branch was changed." }
      when !base_branch_rule_evaluator&.dismiss_stale_reviews_on_push?
        # The clause above ^^^ is the *only* time we dismiss approvals without dismiss_stale_reviews being set.
        # (specifically, we dismiss approvals when a PR is retargeted and only 'last_pusher' is set)
        # From this point, we don't want to dismiss any approvals unless dismiss_stale_reviews is set.
        nil
      when status == :current
        GitHub.dogstats.increment("PullRequest.dismiss_stale_reviews", tags: ["preserved:current"])
        nil
      when status == :stale_head_changed
        GitHub.dogstats.increment("PullRequest.dismiss_stale_reviews", tags: ["reason:stale_head_changed"])
        { via_commit_oid: head_sha }
      when status == :stale_merge_changed
        GitHub.dogstats.increment("PullRequest.dismiss_stale_reviews", tags: ["reason:stale_merge_changed"])
        { message: "The merge-base changed after approval." }
      end

      if reason
        ActiveRecord::Base.connected_to(role: :writing) do
          T.unsafe(review).dismiss!(actor, **reason)
        end
      end
    end
  end

  def dismiss_file_reviews(before:, after:, actor:)
    reviewed_files = user_reviewed_files.where(id: stale_file_reviews(before: before, after: after).map(&:id))
    ActiveRecord::Base.connected_to(role: :writing) do
      reviewed_files.update_all(dismissed: true)
    end

    reviewed_files.each do |reviewed_file|
      GlobalInstrumenter.instrument("pull_request_file.dismissed", {
        repository: repository,
        pull_request: self,
        actor: actor,
        file_path: reviewed_file.filepath,
        action: "DISMISSED",
      })
    end
  end

  # Internal: Determines if we should dismiss stale reviews during synchronize!.
  # We only want to do that if the base protected branch is configured for it and
  # there are changes which we can show in the diff.
  #
  # base_changed_manually - (Optional) A Boolean indicating if the base branch for the PR was changed.
  #
  # Returns a boolean.
  sig { params(changing_base: T::Boolean, base_changed_manually: T::Boolean).returns(T::Boolean) }
  def dismiss_stale_reviews?(changing_base: false, base_changed_manually: false)
    return false unless open?
    # Only look for approvals to dismiss if one of the strict PR review options is enabled
    return false unless base_branch_rule_evaluator&.dismiss_stale_reviews_on_push? ||
      base_branch_rule_evaluator&.require_last_push_approval?
    return true if changing_base

    # See if there are any approvals which are not current
    compute_review_statuses(use_current_base_sha: true).any? do |review, status|
      review.approved? && status != :current
    end
  end

  # Called when PR's head branch is updated and in various other cases (closed PR is re-opened, etc).
  sig { void }
  def find_and_update_last_reviewable_push
    T.bind(self, PullRequest)

    return unless open? && repository

    # By default, only track last reviewable push if a "last push" rule is applied to base branch
    return unless GitHub.flipper[:update_last_reviewable_push_without_rule].enabled?(repository) ||
      base_branch_rule_evaluator&.require_last_push_approval?

    RuleEngine::PullRequestStrictReviewRule.last_reviewable_push_new(self, T.must(self.repository), repositories_domain,
      from_push_job: true)
  end

  # Update the cached value of the last reviewable push. Note that this might occasionally happen while rendering the pull
  # request page. An example of that would be when the PR synch job runs before the HydroRepositoriesOnPushJob has created
  # the new Push record. If we can't find the most recent push for a PR (because it hasn't been created yet), then we can't
  # possibly cache it. That means a new "last push" might be found and cached the next time policies are evalutated.
  sig { params(push_id: Integer, head_sha: String).void }
  def update_last_reviewable_push(push_id:, head_sha:)
    T.bind(self, PullRequest)

    if last_push != nil
      if last_push&.push_id != push_id || last_push&.head_sha != head_sha
        ActiveRecord::Base.connected_to(role: :writing) do
          last_push&.update(push_id: push_id, head_sha: head_sha)
        end
      end
    else
      ActiveRecord::Base.connected_to(role: :writing) do
        PullRequestLastPush.create(repository: self.repository, pull_request: self, push_id:, head_sha:)
      end
    end
  end

  sig { void }
  def delete_last_reviewable_push
    T.bind(self, PullRequest)

    ActiveRecord::Base.connected_to(role: :writing) do
      last_push&.destroy
      last_push = nil
    end
  end

  def dismiss_file_reviews?(before:, after:, base_changed_manually: false)
    stale_file_reviews(before: before, after: after).any? && (base_changed_manually || reviewable_changes?(before: before, after: after))
  end

  # Internal: Determines if there are any reviewable changes between two commit OIDs.
  # Changes are only reviewable if we can produce a diff. For example, empty commits do
  # not constitute reviewable changes. Neither does merging the base branch back into
  # the head branch. Force pushes are considered reviewable changes.
  #
  # before  - The commit OID for the comparison before the changes.
  # after   - The commit OID for the comparison after the changes.
  #
  # Returns a boolean.
  def reviewable_changes?(before:, after:)
    return @reviewable_changes[[before, after]] if defined? @reviewable_changes

    @reviewable_changes = Hash.new do |hash, (before, after)|
      hash[[before, after]] =
        begin
          if before == after
            false
          elsif !(compare_repository.rpc.descendant_of?(after, before))
            true
          else
            current_comparison = current_pull_comparison(before: before, after: after)
            current_comparison && !current_comparison.diffs.empty?
          end
        rescue GitRPC::ObjectMissing
          true
        end
    end

    @reviewable_changes[[before, after]]
  end

  # Similar to `reviewable_changes?` except we just check the diff
  # Used as part of the last pusher policy evaluation
  def has_reviewable_diffs?(before:, after:)
    begin
      if before == after
        false
      else
        merge_base = compare_repository.best_merge_base base_sha, after
        comparison = PullRequest::Comparison.find(
          pull: self,
          start_commit_oid: before,
          end_commit_oid: after,
          base_commit_oid: merge_base)
        return true if comparison.nil? # comparison is nil if there is an issue finding any of the commits
        !comparison.diffs.empty?
      end
    rescue GitRPC::ObjectMissing, GitRPC::InvalidObject => e
      GitHub.dogstats.increment("has_reviewable_diffs.exception", tags: ["exception:#{e.class.name}"])
      true
    end
  end

  def approved_with_no_changes_requested?
    policy_decision = merge_state.pull_request_review_policy_decision
    policy_decision.approved? && !policy_decision.changes_requested?
  end

  # Internal: Returns the users who have submitted a review for a pull request.
  #
  # Returns an ActiveRecord::Relation of Users.
  def submitted_reviewers
    User.where(id: reviews.submitted.pluck(:user_id).uniq)
  end

  def current_head_oid
    T.must(head_repository).heads.find(head_ref)&.target.oid
  end

  private def current_pull_comparison(before:, after:)
    merge_base = compare_repository.best_merge_base base_sha, after

    @current_pull_comparison ||= PullRequest::Comparison.find \
      pull: self,
      start_commit_oid: before,
      end_commit_oid: after,
      base_commit_oid: merge_base
  end
end
