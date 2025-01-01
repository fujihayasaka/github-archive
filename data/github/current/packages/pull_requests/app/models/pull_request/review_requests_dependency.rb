# typed: true
# frozen_string_literal: true

module PullRequest::ReviewRequestsDependency
  include GitHub::Memoizer
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { PullRequest }

  MAX_REVIEW_REQUESTS_FROM_CODE_OWNERS = 100

  # Arbritary limits to speed up type ahead reviewers on initial load.
  TYPE_AHEAD_INITIAL_TEAM_REVIEW_REQUESTS_COUNT = 5
  TYPE_AHEAD_INITIAL_USER_REVIEW_REQUESTS_COUNT = 10

  class_methods do
    def prefill_review_decisions(pulls, current_user)
      Promise.all(pulls.map { |pull| pull.async_review_decision(viewer: current_user) }).sync
    end
  end

  # Public: Return the review request limit from the repo's plan configuration
  #
  # Returns an integer
  def manual_review_requests_limit
    @review_requests_limit ||= T.must(repository).plan_limit(:manual_review_requests)
  end

  def single_manual_review_request?
    manual_review_requests_limit == 1
  end

  # Public: Get a promise that returns the status of this pull request with respect to code review.
  #
  # viewer - a User or nil
  #
  # Returns a promise.
  def async_review_decision(viewer:)
    promises = [async_base_user, async_head_user, async_base_repository, async_user, async_historical_comparison]

    Promise.all(promises).then do
      base_repository = T.must(self.base_repository)
      Promise.all([base_repository.async_internal_repository, base_repository.async_organization]).then do
        cached_merge_state(viewer: viewer).
          async_pull_request_review_policy_decision.then do |policy_decision|
            if policy_decision.changes_requested?
              :changes_requested
            elsif policy_decision.approved?
              :approved
            elsif policy_decision.more_reviews_required?
              if base_branch_rule_evaluator&.pull_request_reviews_required?
                :review_required
              end
            else
              nil
            end
          end
      end
    end
  end

  # Public: Get the status of this pull request with respect to code review.
  #
  # viewer - a User or nil
  #
  # Returns :changes_requested, :approved, :review_required, or nil.
  def review_decision(viewer:)
    async_review_decision(viewer: viewer).sync
  end

  # Internal: Create an review_requested event for a new reviewer.
  #
  # reviewer - The User who was asked to reviewer
  # actor - Optional. The User who made the request.
  #
  # Returns nothing
  def trigger_review_requested_event(review_request, actor: nil)
    issue = T.must(self.issue)
    actor ||= issue.modifying_user
    issue.ignore_duplicate_records do
      events.create(event: "review_requested", actor_id: actor&.id, subject: review_request.reviewer, review_request_id: review_request.id)
    end
    instrument(:create_review_request, actor: actor, reviewer: review_request.reviewer, reviewer_type: review_request.reviewer_type)
    GlobalInstrumenter.instrument("pull_request_review_request.create", {
      actor: actor,
      action: ReviewRequest::REQUESTED_ACTION,
      as_code_owner: review_request.async_as_codeowner?&.sync,
      pull_request: self,
      subject_user: review_request.reviewer,
      subject_type: review_request.reviewer_type,
    })
  end

  # Internal: Create an review_request_removed event when a reviewer is removed unless the remover was a review creation.
  #
  # reviewer - The User whose request was removed
  # actor - Optional. The User who made the request.
  #
  # Returns nothing
  def trigger_review_request_removed_event(reviewer, actor: nil)
    actor ||= T.must(issue).modifying_user
    reviewer_type = reviewer.class.name
    T.must(issue).ignore_duplicate_records do
      events.create(event: "review_request_removed", actor_id: actor&.id, subject: reviewer)
    end
    instrument(:remove_review_request, actor: actor, reviewer: reviewer, reviewer_type: reviewer_type)
    GlobalInstrumenter.instrument("pull_request_review_request.remove", {
      actor: actor,
      action: ReviewRequest::UNREQUESTED_ACTION,
      pull_request: self,
      subject_user: reviewer,
      subject_type: reviewer_type,
    })
  end

  # Public: get the request for this user or team on this review
  #
  # Returns a ReviewRequest or nil if none exist for the given actor
  def direct_review_request_for(actor)
    pending_review_requests_by_reviewer[actor]
  end

  # Internal: returns a cached mapping of reviewers to their review requests
  def pending_review_requests_by_reviewer
    return @pending_review_requests_by_reviewer if defined?(@pending_review_requests_by_reviewer)

    @pending_review_requests_by_reviewer = pending_review_requests.to_a.index_by(&:reviewer)
  end

  # Public: Is review request from this user or team on this pull_request
  #
  # actor - a user or team
  # requests - an optional list of review requests to filter through
  # teams - an optional list of teams to consider; will be calculated from the pending team review
  #         requests on this pull request if omitted
  #
  # Returns a Boolean
  def review_requested_for?(actor, requests: nil, teams: nil)
    review_requests_for(actor, requests: requests, teams: teams).any?
  end

  # Public: What teams (that this user is a member of) have received review
  # requests for this pull request that have been fulfilled
  #
  # Returns a collection of ReviewRequests
  def team_requests_on_behalf_of(user)
    science "team-requests-on-behalf-of-batch-team-check" do |e|
      e.context({ pull_request_id: id })
      e.use do
        T.unsafe(review_requests).fulfilled
          .type_teams
          .order("id DESC")
          .select do |request|
            Team.member_of?(request.reviewer_id, user.id, immediate_only: false)
          end
          .uniq(&:reviewer_id)
      end
      e.try do
        team_review_requests = T.unsafe(review_requests).fulfilled
          .type_teams
          .order("id DESC")

        team_ids = team_review_requests.map(&:reviewer_id)
        results = Promise.all(team_ids.map { |team_id| Platform::Loaders::IsTeamMemberCheck.load(user.id, team_id) }).sync
        membership_by_team = team_ids.zip(results).to_h

        team_review_requests.select { |request| membership_by_team[request.reviewer_id] }.uniq(&:reviewer_id)
      end
      e.compare do |control, candidate|
        control.pluck(:id).to_set == candidate.pluck(:id).to_set
      end
    end
  end

  # Public: Are there any pending review requests for teams that the viewer
  # is a member of
  #
  # Returns a Boolean
  def can_fulfill_a_pending_team_review_request?(user)
    # any? will make sure we don't call `Team.member_of?` more than we need to
    T.unsafe(review_requests).pending.type_teams.any? do |request|
      Team.member_of?(request.reviewer_id, user.id, immediate_only: false)
    end
  end

  # Public: Returns the pending review requests for this pull request.
  def pending_review_requests
    return review_requests if new_record?

    T.unsafe(review_requests)
      .pending
      .preload(:reviewer, :reasons, assigned_from_review_request: [:reviewer, :reasons])
      .group("reviewer_id, pull_request_id, reviewer_type")
      .order("id ASC") # if any duplicates, take the first one created
  end

  def deferred_code_owner_review_requests(existing_requests)
    return [] unless new_record? || draft?

    existing_reviewers = existing_requests.map(&:reviewer)

    T.must(codeowners).owners.each_with_object([]) do |code_owner, deferred_requests|
      next if code_owner == user
      next if existing_reviewers.include?(code_owner)
      next if code_owner_review_fulfilled?(code_owner)

      deferred_requests << ReviewRequest.new(
        pull_request: self,
        reviewer: code_owner,
        deferred_code_owner: true
      )
    end
  end

  def deferred_copilot_review_requests(existing_requests)
    return [] unless new_record? || draft?

    # don't request an automatic review if the bot has ever reviewed this PR
    bot = copilot_review_bot_if_configured_for_automatic_reviews
    return [] if bot.nil? || existing_requests.map(&:reviewer).include?(bot)
    return [] if copilot_review_fulfilled?(bot)

    [ReviewRequest.new(
      deferred: true,
      reviewer: bot,
      pull_request: self,
      deferred_copilot: true
    )]
  end

  # Public: get the requests for this actor on this review
  #
  # actor - a user or team
  # requests - an optional list of review requests to filter through
  # teams - an optional list of teams to consider; will be calculated from the pending team review
  #         requests on this pull request if omitted
  #
  # Returns a list of ReviewRequests
  def review_requests_for(actor, requests: nil, teams: nil)
    return [] if actor.nil?
    return [] if self.user == actor

    requests ||= pending_review_requests
    teams ||= requests.teams
    actors = [actor]

    teams.each do |team|
      if Team.member_of?(team.id, actor.id, immediate_only: false)
        actors.push(team)
      end
    end

    requests.select { |request| actors.include?(request.reviewer) }
  end

  def review_request_removable?(review_request)
    return false if summarize_required_reviewers.any? { _1.team == review_request.reviewer }

    return true unless base_branch_rule_evaluator&.require_code_owner_review?

    # If code owner reviews are enforced, requests to code owners cannot be
    # removed, unless the person requested is no longer a CODEOWNER (i.e. those
    # changes were removed)

    # Return early if this wasn't a codeowners request.
    return true if review_request.reasons.none?(&:codeowners?)

    # If the codeowners object isn't initialized with this pull's
    # changed paths successfully it will appear to fail open, so
    # verify that diff paths were properly loaded after checking
    # that the reviewer is a codeowner.
    !T.must(codeowners).include?(review_request.reviewer) && !codeowners_paths_load_error?
  end

  # Public: Set the full list of reviewers for this pr.
  #
  # reviewers - The full Array of Users and Teams to request review from.
  #             Removes any existing requests unless the reviewer is passed.
  # actor - The User setting the review requests
  # limit - Total number of allowed reviewers to request.
  # should_save - Whether to save the parent record immediately. Default: true.
  # re_request - Is this a re-request of an existing reviewer. Default: false.
  # via_delegation - Is this the result of Team review delegation. If so we'll
  #                  trust that the actor is allowed. The actor may not be a
  #                  repository collaborator if they came via a fork pull and
  #                  CODEOWNERS. Default: false.
  #
  # Returns PullRequest or nil
  def request_review_from(actor:, reviewers: [], limit: manual_review_requests_limit, should_save: true, re_request: false, via_delegation: false, append: false)
    return unless via_delegation ||
      (can_request_reviews = can_request_review?(actor)) ||
      (re_request && can_re_request_review?(actor))

    allowed_reviewers =
      if via_delegation || can_request_team_review?(actor)
        reviewers
      else
        existing_team_reviewers = T.unsafe(review_requests).pending.teams
        reviewers.reject { |reviewer| reviewer.is_a?(Team) } + existing_team_reviewers
      end

    # If the user can only re-request reviews filter the allowed_reviewers to only existing reviewers.
    if !can_request_reviews && !via_delegation
      existing_user_ids = latest_reviews_not_requested.map(&:user_id)
      allowed_reviewers.select! { |reviewer| reviewer.is_a?(Team) || existing_user_ids.include?(reviewer.id) }
    end

    #removed blocked users from the list of allowed reviewers
    allowed_reviewers = allowed_reviewers.reject { |reviewer| reviewer.is_a?(User) && actor.blocked_by?(reviewer.id) }

    allowed_reviewers = allowed_reviewers.reject do |reviewer|
      # reject Copilot if actor doesn't have access
      reviewer == copilot_review_bot && !can_request_review_from_copilot?(actor:)
    end

    pending_reviewers = allowed_reviewers.to_a.first(limit)

    if append
      T.unsafe(review_requests).pending_reviewers.merge(pending_reviewers)
    else
      T.unsafe(review_requests).pending_reviewers = pending_reviewers
    end

    if should_save
      @reviewers_updated = true
      result = save
      # reset this memoized variable since it may have changed
      remove_instance_variable(:@latest_reviews_not_requested) if defined?(@latest_reviews_not_requested)
      result
    end
  end

  # Public: Returns a list of the most recent review that each user has left,
  # as long as the review's status is not pending.
  #
  # Returns Array of PullRequestReviews
  def latest_reviews_not_requested
    # !user to protect against ghost users
    return [] if new_record? || !user
    @latest_reviews_not_requested ||= begin
      # Group-wise maximum against id column rather than updated_at because
      # http://bugs.mysql.com/bug.php?id=54784
      sql = <<-SQL
        SELECT r1.*
        FROM pull_request_reviews r1
        INNER JOIN
        (
          SELECT max(id) as id
          FROM pull_request_reviews
          WHERE pull_request_id = :pull_request_id
          AND pull_request_reviews.state <> :state
          AND user_id <> :pull_user_id
          AND user_id NOT IN (
            SELECT review_requests.reviewer_id
            FROM review_requests
            LEFT OUTER JOIN pull_request_reviews_review_requests on pull_request_reviews_review_requests.review_request_id = review_requests.id
            WHERE review_requests.pull_request_id = :pull_request_id
              AND review_requests.reviewer_type = :type
              AND review_requests.dismissed_at IS NULL
              AND pull_request_reviews_review_requests.review_request_id IS NULL
          )
          GROUP BY user_id
        ) r2
        ON r1.id = r2.id
        ORDER BY r1.state ASC
      SQL

      reviews = PullRequestReview.find_by_sql(Arel.sql(sql,
        pull_request_id: id,
        pull_user_id: T.must(user).id,
        type: "User",
        state: PullRequestReview.state_value(:pending),
      ))

      GitHub::PrefillAssociations.prefill_associations(reviews, :pull_request, available_records: [self])
      reviews
    end
  end

  class_methods do
    # Public: Returns a count per PR of non-stale fulfilled reviews unique by user
    #
    # Returns Hash of PR id's pointing to the count of fulfilled reviews
    # for example,  {12 => 3, 24 => 2} where 12 and 24 are PR id's and they have
    # 3 and 2 fulfilled reviews, respectively.
    def latest_fulfilled_reviews_count_for(pull_request_ids: [])
      reviewer_ids_sql = <<-SQL
        SELECT review_requests.reviewer_id
        FROM review_requests
        LEFT OUTER JOIN pull_request_reviews_review_requests on pull_request_reviews_review_requests.review_request_id = review_requests.id
        WHERE review_requests.pull_request_id IN (:pull_request_ids)
          AND review_requests.reviewer_type = 'User'
          AND review_requests.dismissed_at IS NULL
          AND pull_request_reviews_review_requests.review_request_id IS NULL
      SQL
      reviewer_ids = PullRequestReview.connection.select_rows(Arel.sql(reviewer_ids_sql,
        pull_request_ids: pull_request_ids
      )).to_a.flatten.uniq

      max_id_sql = <<-SQL
        SELECT max(pull_request_reviews.id) as id
        FROM pull_request_reviews
        INNER JOIN pull_requests ON pull_requests.id = pull_request_reviews.pull_request_id
        WHERE pull_request_id IN (:pull_request_ids)
        AND pull_request_reviews.state <> :state
        AND pull_request_reviews.user_id <> pull_requests.user_id
        AND pull_request_reviews.user_id NOT IN (:reviewer_ids)
        GROUP BY pull_request_reviews.user_id, pull_request_reviews.pull_request_id
      SQL
      max_id = PullRequestReview.connection.select_rows(Arel.sql(max_id_sql,
        pull_request_ids: pull_request_ids,
        state: PullRequestReview.state_value(:pending),
        reviewer_ids: reviewer_ids.empty? ? [0] : reviewer_ids
      )).flatten

      return {} if max_id.empty?

      sql = <<-SQL
        SELECT pull_request_id, COUNT(id) AS fulfilled_reviews_count
        FROM pull_request_reviews
        WHERE id in (:max_id)
        GROUP BY pull_request_id
        LIMIT 1000
      SQL

      query = Arel.sql(sql, max_id: max_id)
      PullRequestReview.connection.select_rows(query).to_h
    end
  end

  # Order by current user, requested reviewers, then other reviewers sorted alphabetically.
  #
  # current_user - the viewing user
  # requests - an optional list of review requests to filter through
  #
  # Returns Array of Users and Teams.
  def sorted_reviewers(current_user, requests: nil, search_query: nil)
    use_type_ahead = !search_query.nil?

    search_query = ActiveRecord::Base.sanitize_sql_like(search_query) if use_type_ahead
    users = available_review_users(use_type_ahead, search_query).filter_spam_for(current_user).sort_by { |u| u.login.downcase }

    requests ||= pending_review_requests
    reviewers = requests.map(&:reviewer)
    users -= reviewers
    users = reviewers + users

    if current_user && users.delete(current_user)
      users.unshift(current_user)
    end

    teams = if can_request_team_review?(current_user)
      (available_review_teams(use_type_ahead: use_type_ahead, search_query: search_query) - reviewers).sort_by { |t| t.name.downcase }
    else
      []
    end
    (users + teams).compact
  end

  # Check to see what users can be requested
  # includes users that collaborators (:read or :write)
  # If we have type ahead enabled, we will filter down further to match for the `search_query`,
  # or if the `search_query` is empty, we will limit the results to speed up the initial query.
  #
  # Returns an array of Users.
  def available_review_users(use_type_ahead, search_query)
    @available_reviewer_users ||= begin
      if !use_type_ahead
        User.where(id: available_review_user_ids).includes(:profile)
      elsif search_query.empty?
        # If we have an empty search query, this means type-ahead is enabled. we will limit the query to speed up initial load,
        # as the intention is for the user to filter down further with typing a valid search.
        User.where(id: available_review_user_ids).limit(TYPE_AHEAD_INITIAL_USER_REVIEW_REQUESTS_COUNT).includes(:profile)
      else
        users = User.preload(:profile)
          .left_joins(:profile)
          .select("users.id, users.login, users.display_login, users.source_login, users.type, users.created_at, users.business_id")
          .where(id: available_review_user_ids)
          .merge(User.where("login LIKE ?", "%#{search_query}%").or(Profile.where("name LIKE ?", "%#{search_query}%")))
          .references(:profile)
      end
    end
  end

  def available_review_user_ids(filter: nil)
    filter_ids = filter.map(&:id) if filter
    privileged_ids = T.must(issue).user_ids_with_privileged_access(actor_ids_filter: filter_ids).
      select { |id| id != user&.id }.compact

    if T.must(repository).public?
      existing_reviewer_ids = latest_reviews_not_requested.map(&:user_id)
      privileged_ids += existing_reviewer_ids
    end

    privileged_ids - suspended_user_ids(privileged_ids)
  end

  def suspended_user_ids(privileged_ids)
    return [] if privileged_ids.empty?
    User.where(id: privileged_ids).suspended.pluck(:id)
  end

  # Check to see what teams can be requested.
  # If we have type ahead enabled, we will filter down further to match for the `search_query`,
  # or if the `search_query` is empty, we will limit the results to speed up the initial query.
  #
  # Returns an array of Teams.
  def available_review_teams(filter: nil, use_type_ahead: false, search_query: nil)
    repository = T.must(self.repository)
    return [] unless repository.in_organization?

    if use_type_ahead
      scope = repository.teams(immediate_only: false).closed.where(organization_id: repository.organization&.id)
      if search_query.empty?
        # If we have an empty search query, this means type-ahead is enabled. we will limit the query to speed up initial load,
        # as the intention is for the user to filter down further with typing a valid search.
        scope.limit(TYPE_AHEAD_INITIAL_TEAM_REVIEW_REQUESTS_COUNT)
      else
        # If we have a valid search query, it is actually impossible to use LIKE in any effective manner (as we do we the user).
        # This is because, we prefix the organization name to the team name, such as `github/issues`, but in the database we simply store only `issues`.
        # This means majority of the search queries will not correctly find the team at the database level, so we have to do it in memory.
        scope.select { |team| team.to_s.downcase.include? search_query.downcase }
      end
    else
      # We only want to cache that use the filter logic, not for type-ahead.
      @available_review_teams ||= {}
      @available_review_teams[filter] ||= if filter
        filter_ids = filter.map(&:id)
        repository.teams(immediate_only: false).closed.
          where(organization_id: repository.organization&.id, id: filter_ids)
      else
        repository.teams(immediate_only: false).closed.where(organization_id: repository.organization&.id)
      end
    end
  end

  # Public: Filters a list of users down to only those who are allowed to
  # be requested for review.
  #
  # mixed_reviewers   - An Array of Users and/or Teams to request review from.
  #
  # Returns an Array of Users and/or Teams.
  def filter_allowed_reviewers(mixed_reviewers, actor: nil)
    reviewer_groups = mixed_reviewers.group_by(&:class)
    users = reviewer_groups[User] || []
    teams = reviewer_groups[Team] || []
    bots  = reviewer_groups[Bot] || []

    allowed_user_ids = available_review_user_ids(filter: users)
    allowed_users = users.select { |u| allowed_user_ids.include?(u.id) }

    allowed_teams = teams.select { |t| available_review_teams(filter: teams).include?(t) }
    if actor.nil? || can_request_team_review?(actor)
      allowed_users += allowed_teams
    end

    review_app = Apps::Privileged.integration(:copilot_pull_request_reviewer)
    if review_app.present?
      allowed_users += bots.select { |b| b.id == review_app.bot.id }
    end

    allowed_users
  end

  def can_request_review_from?(reviewer)
    filter_allowed_reviewers([reviewer]).include?(reviewer)
  end

  def can_request_team_review?(actor)
    repository = T.must(self.repository)

    return false unless repository.in_organization?
    return false unless repository.plan_supports?(:team_review_requests)
    return false unless actor.present?

    if actor.can_have_granular_permissions?
      repository.organization&.resources.members.readable_by?(actor)
    else
      # repo collaborators cannot request team review
      repository.organization&.direct_or_team_member?(actor)
    end
  end

  # Only return reviews that are not spammy
  #
  # Returns Array of PullRequestReviews
  def visible_sidebar_reviews(viewer)
    latest_reviews_not_requested.reject do |review|
      !review.show_in_sidebar? || review.hide_from_user?(viewer)
    end
  end

  # Only return requests that are not spammy
  # and viewer can view the team request
  # Returns Array of RequestReviews
  def visible_sidebar_requests(viewer, existing_requests)
    existing_requests.reject do |request|
      !request.visible_subject_for(viewer)
    end
  end

  # Public: Can the user request a review?
  #
  # Returns Boolean
  def can_request_review?(actor)
    async_can_request_review?(actor).sync
  end

  def async_can_request_review?(actor)
    return Promise.resolve(false) unless actor

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :request_pr_review,
      actor: actor,
      subject: self,
    ).then do |decision|
      decision.allow?
    end
  end

  # Public: Can a user re-request a review? When a review request is
  # auto-generated by CODEOWNERS, the PR author should be able to re-request
  # review when they have read-only access.
  #
  # Returns a Boolean.
  def async_can_re_request_review?(actor)
    return Promise.resolve(true) if actor == user

    async_can_request_review?(actor)
  end

  def can_re_request_review?(actor)
    async_can_re_request_review?(actor).sync
  end

  # Public: Should reviewer suggestions be returned for this pull request?
  #
  # user - the currently authenticated user
  #
  # Returns a Boolean.
  def include_reviewer_suggestions?(user: nil)
    can_request_review?(user) && suggested_reviewers_available?(actor: user) && suggested_reviewers(actor: user).any?
  end

  # Check who requested this user for review
  # user - the user who is being requested
  #
  # Returns User
  def user_requesting(user)
    @request_events ||= events.select(&:review_requested?).select do |event|
      if event.subject.is_a?(Team)
        event.subject.member?(user)
      else
        event.subject == user
      end
    end
    @request_events.last&.actor
  end

  def async_user_requesting(user)
    Platform::Loaders::IssueEventsByEvent.load(issue_id: T.must(issue).id, event_type: :review_requested).then do |events|
      events.reverse.find do |event|
        event.async_subject.then do |subject|
          if subject.is_a?(Team)
            subject.member?(user)
          else
            subject == user
          end
        end
      end&.async_actor
    end
  end

  # Should we show suggestions for this pull request?
  def suggested_reviewers_available?(actor: nil)
    (!persisted? || open?) && PullRequest::SuggestedReviewers.new(self, actor: actor).available?
  end

  # Suggest users to review this pull request.
  #
  # requests - an optional list of review requests to filter through
  # teams - an optional list of teams to consider; will be calculated from the pending team review
  #         requests on this pull request if omitted
  # actor - an optional current actor/user
  #
  # Returns an Array of SuggestedReviewer.
  def suggested_reviewers(requests: nil, teams: nil, actor: nil)
    @suggested_reviewers ||= begin
      suggester = PullRequest::SuggestedReviewers.new(self, actor: actor)
      suggestions = suggester.find(excluding: user)
      suggestions.reject do |suggestion|
        review_requested_for?(suggestion.user, requests: requests, teams: teams)
      end
    rescue GitRPC::Timeout => error
      GitHub.dogstats.increment("pull_request.suggested_reviewers.timeout")
      []
    end
  end

  # Public: Enqueue a job to create codeowners review requests.
  #
  # user - the User who will be credited for creating the review request
  def enqueue_request_pull_request_reviewers_job(actor: user, should_re_request_reviews: false)
    RequestPullRequestReviewersJob.perform_later(self, actor, should_re_request_reviews: should_re_request_reviews)
  end

  # Public: Request review from codeowners
  # If protected branches turned on also require the requests
  #
  # actor - the User doing the requesting
  # should_save - we only need to save the PR if it is being created for the first time
  #               see bug reported in https://github.com/github/github/pull/76198
  def request_review_from_codeowners(actor, should_save: false)
    return if codeowners!.none?

    # Don't request review if owner has already left a review
    owners_to_request = T.must(codeowners).reject { |owner| code_owner_review_fulfilled?(owner) }

    # Don't request review if owner has already dismissed an automated request
    owners_to_request = owners_to_request.reject { |owner| dismissed_automated_request_for?(owner) }

    # Limit the maximum number of code owners we'll request review from
    owners_to_request = owners_to_request.first(MAX_REVIEW_REQUESTS_FROM_CODE_OWNERS)

    owners_to_request.each do |owner|
      rules = T.must(codeowners).rules_by_owner[owner].uniq
      reasons = rules.map do |rule|
        { tree_oid: T.must(codeowners).tree_oid, path: T.must(codeowners).path, line: rule.line, pattern: rule.pattern.to_s }
      end

      ActiveRecord::Base.connected_to(role: :writing) do
        T.unsafe(review_requests).add_pending_reviewer_with_reasons(owner, reasons: { codeowners: reasons })
      end
    end

    self.save if should_save
  end

  def add_missing_required_review_requests(missing_reviewer_summaries: nil, should_save: false)
    missing_reviewer_summaries ||= find_missing_required_review_summaries

    return unless missing_reviewer_summaries.present? && repository

    missing_reviewer_summaries.each { |summary| add_pending_reviewer(summary.team) }

    self.save if should_save
  end

  def find_missing_required_review_summaries
    T.bind(self, ::PullRequest)
    required_reviewer_summaries = self.summarize_required_reviewers

    teams_already_requested = T.unsafe(review_requests).not_dismissed.type_teams.map(&:reviewer)

    required_reviewer_summaries.reject { teams_already_requested.include?(_1.team) }
  end

  # Public: Find reviewers who are required by ref-update rules but not assigned to this PR
  def summarize_required_reviewers
    T.bind(self, ::PullRequest)
    @required_reviewer_summary ||= RuleEngine::PullRequestStrictReviewRule::summarize_required_reviewers(self)
  end

  def request_review_from_copilot(actor)
    return if draft? || repository.nil?

    # don't request an automatic review if the bot has ever reviewed this PR
    bot = copilot_review_bot_if_configured_for_automatic_reviews
    return if bot.nil? || reviews_for(bot).any? || direct_review_request_for(bot).present?

    # add the bot for review!
    add_pending_reviewer(bot)
    self.save
  end

  def copilot_review_bot_if_configured_for_automatic_reviews
    access = PullRequests::Copilot::CodeReviewAccess.new(
      actor: self.user,
      pull_request: T.unsafe(self),
      current_repository: T.must(self.base_repository)
    )
    return unless access.auto_reviewable? || access.repo_rule_auto_reviewable?

    copilot_review_bot
  end

  def can_request_review_from_copilot?(actor:)
    return false if copilot_review_bot.nil?

    PullRequests::Copilot::CodeReviewAccess.new(
      actor:,
      pull_request: T.unsafe(self),
      current_repository: T.must(self.base_repository)
    ).can_create_review_request?
  end

  memoize def copilot_review_bot
    app = ::Apps::Privileged.integration(:copilot_pull_request_reviewer)
    return if app.nil?
    app.bot
  end

  # Public: Add a pending review request.
  #
  # reviewer - the User being requested.
  def add_pending_reviewer(reviewer)
    T.unsafe(review_requests).add_pending_reviewer_with_reasons(reviewer)
  end

  def code_owner_review_fulfilled?(code_owner)
    if code_owner.is_a?(User)
      !!latest_non_pending_review_for(code_owner)
    else
      T.unsafe(review_requests).fulfilled.for(code_owner).any?
    end
  end

  def copilot_review_fulfilled?(copilot_bot)
    !!latest_non_pending_review_for(copilot_bot)
  end

  def dismissed_automated_request_for?(reviewer)
    dismissed_automated_reviewers.include?(reviewer)
  end

  def dismissed_automated_reviewers
    @dismissed_reviewers ||= T.unsafe(unscoped_review_requests).dismissed.automated.reviewers
  end

  def team_review_requests_for(reviewers)
    T.unsafe(review_requests).pending.where(reviewer_id: reviewers.map(&:id), reviewer_type: "Team")
  end

  def user_review_requests_for(reviewers)
    T.unsafe(review_requests).pending.where(reviewer_id: reviewers.map(&:id), reviewer_type: "User")
  end
end
