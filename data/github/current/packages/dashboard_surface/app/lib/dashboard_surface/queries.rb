# typed: strict
# frozen_string_literal: true

module DashboardSurface
  module Queries
    # Default view query
    DEFAULT_QUERY = "is:pr (author:@me OR (author:@copilot assignee:@me)) archived:false sort:updated-desc state:open"
    DEFAULT_QUERY_EXPANDED = "is:pr author:@me archived:false sort:updated-desc state:open"

    # Sidebar link queries — used as URL params in the UI sidebar navigation
    # // !! CAUTION !! If you modify any 'query' field values here, they must also be updated in the UI implementation in the github/github-ui repo at: packages/dashboard-surface/helpers/query-resolver.ts
    AUTHORED_QUERY = "is:pr (author:@me OR (author:@copilot assignee:@me)) state:open archived:false sort:updated-desc"
    AUTHORED_QUERY_EXPANDED = "is:pr author:@me state:open archived:false sort:updated-desc"
    ASSIGNED_QUERY = "is:pr assignee:@me state:open archived:false sort:updated-desc"
    INVOLVES_QUERY = "is:pr involves:@me state:open archived:false sort:updated-desc"
    REVIEW_QUERY = "is:pr review-requested:@me state:open archived:false sort:updated-desc"

    # Named ES queries for each inbox section.
    # Single-query sections have one-element arrays; composite sections have multiple.
    READY_TO_MERGE_QUERY = "is:pr author:@me state:open -is:draft archived:false sort:updated-desc"
    READY_TO_MERGE_QUERY_WITH_REVIEW = "is:pr author:@me state:open -is:draft review:approved -review:changes_requested -status:failure -is:queued archived:false sort:updated-desc"
    REVIEW_REQUESTED_QUERY = "is:pr user-review-requested:@me state:open archived:false sort:updated-desc"
    TEAM_REVIEW_REQUESTED_QUERY = "is:pr team-review-requested-user:@me state:open archived:false sort:updated-desc"
    YOUR_DRAFTS_QUERY = "is:pr author:@me is:draft state:open archived:false sort:updated-desc"
    WAITING_FOR_REVIEW_QUERY = "is:pr author:@me state:open -is:draft archived:false -review:approved -review:changes_requested -status:failure sort:updated-desc"
    MERGE_QUEUE_QUERY = "is:pr is:queued state:open (author:@me OR (author:@copilot assignee:@me)) archived:false sort:updated-desc"
    MERGE_QUEUE_QUERY_EXPANDED = "is:pr is:queued state:open author:@me archived:false sort:updated-desc"

    # "Needs action" captures PRs that require attention, including those with
    # changes requested, failing checks, or agent-owned PRs that are blocking
    # you. The inbox controller now executes the unified path through
    # Search::Queries::InboxNeedsActionQuery while the config layer retains the
    # legacy sub-queries for composite behavior and suffix expansion.
    NEEDS_ACTION_CHANGES_REQUESTED_QUERY = "is:pr author:@me state:open review:changes_requested archived:false sort:updated-desc -is:draft"
    NEEDS_ACTION_FAILING_CHECKS_QUERY = "is:pr author:@me state:open status:failure archived:false sort:updated-desc -is:draft"
    NEEDS_ACTION_AGENT_BLOCKED = "is:pr -is:closed archived:false author:@copilot assignee:@me (status:failure OR review:changes_requested) sort:updated-desc -is:draft"
    NEEDS_ACTION_ACTIVE_REVIEW_QUERY = "is:pr author:@me state:open review:required comments:>0 archived:false sort:updated-desc -is:draft"

    sig { params(user: T.nilable(User)).returns(String) }
    def self.default_query_for(user)
      agent_author_expansion_enabled?(user) ? DEFAULT_QUERY_EXPANDED : DEFAULT_QUERY
    end

    sig { params(user: T.nilable(User)).returns(String) }
    def self.authored_query_for(user)
      agent_author_expansion_enabled?(user) ? AUTHORED_QUERY_EXPANDED : AUTHORED_QUERY
    end

    sig { params(user: T.nilable(User)).returns(String) }
    def self.merge_queue_query_for(user)
      agent_author_expansion_enabled?(user) ? MERGE_QUEUE_QUERY_EXPANDED : MERGE_QUEUE_QUERY
    end

    sig { params(user: T.nilable(User)).returns(T::Boolean) }
    def self.agent_author_expansion_enabled?(user)
      return false unless user

      FeatureFlag.vexi.enabled?(:agent_author_search_expansion, user, default: false)
    end
  end
end
