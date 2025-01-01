# typed: true
# frozen_string_literal: true

class Team
  module ReviewRequestDelegation
    include Kernel
    class DelegationError < StandardError; end

    class Result
      def self.success(delegates:)
        new(delegates: delegates)
      end

      def self.failure(error:)
        new(error: error)
      end

      attr_reader :delegates, :error

      def initialize(delegates: [], error: nil)
        @delegates = delegates
        @error = error
      end

      def success?
        error.nil?
      end
    end

    extend self

    # Database level limit, used to validate Team#review_request_delegation_member_count
    # Before changing this value, confirm via datadot that changes will not impact existing team records
    DELEGATE_LIMIT = 10
    MEMBER_LIMIT = 1_000

    # Public: Delegate a team review request to one or more team members by a chosen algorithm.
    #
    # actor - The User-ish the delegation will be attributed to.
    # pull_request - The PullRequest to delegate a team review request on.
    # team - The Team that has had its review requested.
    # max_auto_assigned_reviewers_count - A Fixnum count of members to delegate to, between 1 and DELEGATE_LIMIT.
    #                    (Default: 1).
    # strategy - The Symbol algorithm for selecting delegates, either :round_robin or :load_balance.
    # count_existing_reviewers - A boolean, whether team members whose review has already been
    #                            requested should count against max_auto_assigned_reviewers_count. (Default: true).
    # remove_team_request - A boolean indicating whether the team review request should be removed.
    #                       (Default: true.)
    # include_child_team_members - A boolean indicating whether the members of child teams should be
    #                              included in review assignment. (Default: true.)
    # window_in_days - For the :load_balance strategy, the window back in time to consider request load.
    #
    # Given a team review request on a pull request, will request one or more specific team
    # members to review that pull request, optionally removing the team request.
    #
    # Selection algorithms:
    #
    # - Round robin: Selected by when the members were last delegated to, least-recently first.
    # - Load balance: Selected by the number of review requests they have received in the past N days, least-first
    #
    # Elegible team members for selection:
    #
    #   - Aren't the PR author
    #   - Don't have an existing review request on the PR
    #   - That haven't left an approved and not-dismissed approval
    #   - Don't have a "busy" user status on the team's organization
    #
    # Returns a Result with delegated-to Users on success, or explantory error on failure.
    def delegate_to_members(
      actor:,
      pull_request:,
      team:,
      strategy:,
      max_auto_assigned_reviewers_count: 1,
      count_existing_reviewers: true,
      remove_team_request: true,
      include_child_team_members: true,
      window_in_days: 30
    )
      return if !pull_request.review_requested_for?(team)

      result = \
        case strategy
        when :round_robin
          round_robin_delegates(
            pull_request: pull_request,
            team: team,
            max_auto_assigned_reviewers_count: max_auto_assigned_reviewers_count,
            count_existing_reviewers: count_existing_reviewers,
            include_child_team_members: include_child_team_members,
          )
        when :load_balance
          load_balance_delegates(
            pull_request: pull_request,
            team: team,
            max_auto_assigned_reviewers_count: max_auto_assigned_reviewers_count,
            count_existing_reviewers: count_existing_reviewers,
            include_child_team_members: include_child_team_members,
            window_in_days: window_in_days,
          )
        else
          raise ArgumentError.new("Unknown delegation strategy: #{strategy}")
        end

      if !result.success?
        GitHub.logger.info(
          "Review Request: Delegate to members failed",
          "code.algorithm": strategy,
          "code.failure": result.error,
          "gh.actor.id": actor.id,
          "gh.pull_request.id": pull_request.id,
          "gh.org.id": team.organization_id,
          "gh.org.team.id": team.id,
          "gh.org.team.name": team.name,
          "gh.repository.id": pull_request.repository_id,
          "gh.review_request.action": ReviewRequest::REQUESTED_ACTION
        )
        return result
      end

      if result.delegates.empty?
        GitHub.logger.info(
          "Review Request: Delegate to members returned zero delgates",
          "code.algorithm": strategy,
          "code.failure": result.error,
          "gh.actor.id": actor.id,
          "gh.pull_request.id": pull_request.id,
          "gh.org.id": team.organization.id,
          "gh.org.team.id": team.id,
          "gh.org.team.name": team.name,
          "gh.repository.id": pull_request.repository_id,
          "gh.review_request.action": ReviewRequest::REQUESTED_ACTION
        )
        return result
      end

      pending_review_requests = pull_request.review_requests.pending.preload(:reviewer)
      reviewers = pending_review_requests.map(&:reviewer)

      team_review_request = pending_review_requests.find { |rr| rr.reviewer == team }

      if remove_team_request && team_review_request && pull_request.review_request_removable?(team_review_request)
        reviewers -= [team]
      end

      result.delegates.each { |d| d.review_request_assigned_from = team_review_request }
      reviewers -= result.delegates
      reviewers.concat(result.delegates)

      pull_request.request_review_from(
        actor: actor,
        reviewers: reviewers,
        limit: reviewers.count,
        should_save: true,
        via_delegation: true,
      )

      assigned_review_requests = \
        # Filter and sort in memory to avoid another db query
        pull_request.review_requests.select do |rr|
          rr.pending? && rr.assigned_from_review_request_id == team_review_request&.id
        end.sort

      params = {
        organization: team.organization,
        team: team,
        repository: pull_request.repository,
        pull_request: pull_request,
        algorithm: strategy,
        max_delegated_reviewers_count: max_auto_assigned_reviewers_count,
        count_existing_reviewers: count_existing_reviewers,
        remove_team_request: remove_team_request,
        include_child_team_members: include_child_team_members,
        team_review_request: team_review_request,
        assigned_review_requests: assigned_review_requests,
        actor: actor,
        action: ReviewRequest::REQUESTED_ACTION,
      }
      GlobalInstrumenter.instrument("pull_request.review_request_delegated", params)

      result
    end

    # Internal: Round robin selection of team members for review delegation.
    #
    # pull_request - The PullRequest to delegate a team review request on.
    # team - The Team that has had its review requested.
    # max_auto_assigned_reviewers_count - A Fixnum count of members to delegate to, between 1 and DELEGATE_LIMIT.
    #                    (Default: 1).
    # count_existing_reviewers - Whether team members whose review has already been requested
    #                            should count against max_auto_assigned_reviewers_count. (Default: true).
    # include_child_team_members - Whether members of child teams should be included as candidates.
    #
    # Selection algorithm:
    #
    # - Pick team members that:
    #     - Aren't the PR author
    #     - Don't have an existing review request on the PR
    #     - That haven't left an approved and not-dismissed approval
    #     - Don't have a "busy" user status on the team's organization
    # - Ordered by the when they were last delegated to, least-recently first.
    # - Limited to the max needed number of reviewers, M
    #
    # Returns a Result with a User Relation scoped to the candidate delegates found on success, or explantory error on failure.
    def round_robin_delegates(pull_request:, team:, max_auto_assigned_reviewers_count: 1, count_existing_reviewers: true, include_child_team_members: true)
      find_candidate_delegates_using_sort(pull_request, team, max_auto_assigned_reviewers_count, count_existing_reviewers, include_child_team_members) do |candidate_ids|
        # find_candidate_delegates_using_sort writes to the TeamMemberDelegatedReviewRequesttable so ensure we read from the primary to avoid replication lag issues.
        delegated_at_by_member_id = ActiveRecord::Base.connected_to(role: :writing) do
          TeamMemberDelegatedReviewRequest.where(
            team_id: team.id,
            member_id: candidate_ids,
          ).pluck(:delegated_at, :member_id).index_by { |(_, id)| id }
        end

        # Sort by least-recent delegation first. Nil means the user has
        # never been delegated to, so sort nil values earliest.
        candidate_ids.sort do |id1, id2|
          id1_delegated_at = delegated_at_by_member_id[id1]
          id2_delegated_at = delegated_at_by_member_id[id2]
          if id1_delegated_at.nil?
            next 0 if id2_delegated_at.nil?
            next -1
          end
          next 1 if id2_delegated_at.nil?
          id1_delegated_at <=> id2_delegated_at
        end
      end
    end

    # Internal: Load balanced selection of team members for review delegation.
    #
    # pull_request - The PullRequest to delegate a team review request on.
    # team - The Team that has had its review requested.
    # max_auto_assigned_reviewers_count - A Fixnum count of members to delegate to, between 1 and DELEGATE_LIMIT.
    #                    (Default: 1).
    # count_existing_reviewers - Whether team members whose review has already been requested
    #                            should count against max_auto_assigned_reviewers_count. (Default: true).
    # include_child_team_members - Whether members of child teams should be included as candidates.
    # window_in_days - The number of days before now to consider request volume for load balancing.
    #
    # Selection algorithm:
    #
    # - Pick team members that:
    #     - Aren't the PR author
    #     - Don't have an existing review request on the PR
    #     - That haven't left an approved and not-dismissed approval
    #     - Don't have a "busy" user status on the team's organization
    # - Ordered by the number of review requests they have received in the past N days, least-first
    # - Limited to the max needed number of reviewers, M
    #
    # Returns a Result with a User Relation scoped to the candidate delegates found on success, or explantory error on failure.
    def load_balance_delegates(pull_request:, team:, max_auto_assigned_reviewers_count: 1, count_existing_reviewers: true, include_child_team_members: true, window_in_days: 30)
      find_candidate_delegates_using_sort(pull_request, team, max_auto_assigned_reviewers_count, count_existing_reviewers, include_child_team_members) do |candidate_ids|
        next [] if candidate_ids.empty?

        ordered_candidate_ids_with_requests = candidate_reviewer_ids(candidate_ids, team.organization_id, Time.current - window_in_days.days, MEMBER_LIMIT)

        # The INNER JOIN within candidate_reviewer_ids means we'll lose the ids of any members that haven't yet
        # received review requests. Below we'll prepend any lost ids to the query results.

        candidate_ids_with_zero_requests = candidate_ids - ordered_candidate_ids_with_requests

        candidate_ids_with_zero_requests.sort!

        candidate_ids_with_zero_requests.concat(ordered_candidate_ids_with_requests)
      end
    end

    def candidate_reviewer_ids(reviewer_ids, org_id, since, limit)
      reviewer_repository_ids = ReviewRequest.
        joins(:pull_request).
        where(reviewer_id: reviewer_ids).
        where("review_requests.created_at > ?", since).
        select("pull_requests.repository_id").
        distinct.
        pluck("pull_requests.repository_id")
      return [] unless reviewer_repository_ids.size > 0

      org_repo_ids = Repositories::Public.filter_repo_ids_to_org(repo_ids: reviewer_repository_ids, organization_id: org_id).pluck(:id)
      return [] unless org_repo_ids.size > 0

      ReviewRequest.
        joins(:pull_request).
        where(reviewer_id: reviewer_ids).
        where(pull_request: { repository_id: org_repo_ids }).
        where("review_requests.created_at > ?", since).
        group("review_requests.reviewer_id").
        order("review_requests_reviewer_id_count, review_requests.reviewer_id").
        limit(limit).
        pluck("review_requests.reviewer_id, COUNT(review_requests.reviewer_id) as review_requests_reviewer_id_count").
        map(&:first) # needed because of https://github.com/vitessio/vitess/issues/11219
    end

    # Private: Finds a set of team members who could be delegated to from a given sorting routine.
    #
    # pull_request - The PullRequest to delegate a team review request on.
    # team - The Team that has had its review requested.
    # max_auto_assigned_reviewers_count - A Fixnum count of members to delegate to, between 1 and DELEGATE_LIMIT.
    # count_existing_reviewers - Whether team members whose review has already been requested
    #                            should count against max_auto_assigned_reviewers_count.
    # include_child_team_members - Whether members of child teams should be included as candidates.
    # block - A Proc object taking an Array of member ids and returning a sorted Array from
    #         those ids, ordered by priority; the first max_auto_assigned_reviewers_count will be the delegates.
    #
    # Returns a Result with a User Relation scoped to the candidate delegates found on success, or explantory error on failure.
    private def find_candidate_delegates_using_sort(pull_request, team, max_auto_assigned_reviewers_count, count_existing_reviewers, include_child_team_members, &block)
      if max_auto_assigned_reviewers_count > DELEGATE_LIMIT || max_auto_assigned_reviewers_count < 1
        raise ArgumentError.new("Between 1 and #{DELEGATE_LIMIT} reviewers may be delegated to. Requested: #{max_auto_assigned_reviewers_count}.")
      end

      requested_reviewer_ids =
        pull_request.review_requests.pending.not_dismissed.type_users.pluck(:reviewer_id)
      excluded_member_ids = ReviewRequestDelegationExcludedMember.where(team_id: team.id).pluck(:user_id)
      approver_ids = pull_request.reviews.where(state: PullRequestReview.state_value(:approved)).pluck(:user_id)

      member_ids = (include_child_team_members ? team.descendant_or_self_member_ids : team.member_ids).take(MEMBER_LIMIT)

      candidate_member_ids = member_ids - ([pull_request.user_id] + requested_reviewer_ids + approver_ids + excluded_member_ids)

      if count_existing_reviewers
        requested_member_ids = requested_reviewer_ids & member_ids
        max_auto_assigned_reviewers_count -= requested_member_ids.length

        if max_auto_assigned_reviewers_count < 1
          return Result.success(delegates: [])
        end
      end

      if candidate_member_ids.empty?
        return Result.failure(error: DelegationError.new("No team members were available for review."))
      end

      already_requested_reviewers_count = requested_reviewer_ids.count
      spaces_left = pull_request.manual_review_requests_limit - already_requested_reviewers_count
      if spaces_left > 0
        needed_reviewers = [max_auto_assigned_reviewers_count, spaces_left].min
      else
        GitHub.dogstats.increment("pull_requests.review_request_delegation.over_review_request_limit")
        return Result.success(delegates: [])
      end

      active_candidate_member_ids = Team.connection.select_values(Arel.sql(<<-SQL, team_id: team.id, candidate_member_ids: candidate_member_ids, now: Time.current))
        SELECT u.id
        FROM users u
        LEFT JOIN user_statuses us
          ON u.id = us.user_id AND us.limited_availability = 1
          AND (us.expires_at > :now OR us.expires_at IS NULL)
        WHERE u.id IN (:candidate_member_ids)
          AND us.id IS NULL
      SQL

      delegate_ids = yield(active_candidate_member_ids).first(needed_reviewers)

      if delegate_ids.empty?
        return Result.failure(error: DelegationError.new("No team members were available for review."))
      end

      delegated_at = Time.current

      # This writes to the collab DB cluster which we have a read-only connection to by default
      # in the SynchronizePullRequestJob so we need to be explicit about needing a write connection.
      ActiveRecord::Base.connected_to(role: :writing) do
        delegate_ids.each do |id|
          TeamMemberDelegatedReviewRequest.upsert(
            team_id: team.id,
            member_id: id,
            delegated_at: delegated_at,
          )
        end
      end

      Result.success(delegates: User.where(id: delegate_ids))
    end
  end
end
