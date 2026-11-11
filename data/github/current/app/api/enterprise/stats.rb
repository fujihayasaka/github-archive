# typed: true
# frozen_string_literal: true

class Api::Enterprise::Stats < Api::App
  map_to_service :orgs, only: [ # rubocop:todo GitHub/MapToService
    "GET /enterprise/stats/orgs"
  ]
  map_to_service :enterprise_accounts, only: [ # rubocop:todo GitHub/MapToService
    "GET /enterprise/stats/all",
    "GET /enterprise/stats/comments",
    "GET /enterprise/stats/gists",
    "GET /enterprise/stats/users"
  ]
  map_to_service :repos, only: [ # rubocop:todo GitHub/MapToService
    "GET /enterprise/stats/repos",
  ]
  map_to_service :pages, only: [ # rubocop:todo GitHub/MapToService
    "GET /enterprise/stats/pages",
  ]
  map_to_service :pull_requests, only: [ # rubocop:todo GitHub/MapToService
    "GET /enterprise/stats/pulls",
  ]
  map_to_service :issues, only: [ # rubocop:todo GitHub/MapToService
    "GET /enterprise/stats/issues",
    "GET /enterprise/stats/milestones",
  ]

  # These stats are primarily for use with Enterprise. Most of this data
  # is collected and used via statsd with .com, but we don't have any kind
  # of statsd infrastructure working with Enterprise yet. In the mean time,
  # we need to provide some metrics to make Enterprise admins happy. As
  # better methods become available we can replace this stuff with it.

  STATS = GitHub::Stats::Site

  get "/enterprise/stats/all", operation_id: "enterprise-admin/get-all-stats" do
    unless trusted_port?
      control_access :enterprise,
        resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    deliver_raw(
      repos: STATS.repo_stats,
      hooks: STATS.hook_stats,
      pages: STATS.page_stats,
      orgs: STATS.org_stats,
      users: STATS.user_stats,
      pulls: STATS.pull_request_stats,
      issues: STATS.issue_stats,
      milestones: STATS.milestone_stats,
      gists: STATS.gist_stats,
      comments: STATS.comment_stats,
    )
  end

  get "/enterprise/stats/repos", operation_id: "enterprise-admin/get-repo-stats" do
    unless trusted_port?
      control_access :enterprise,
        resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    deliver_raw STATS.repo_stats
  end

  get "/enterprise/stats/hooks", operation_id: "enterprise-admin/get-hooks-stats" do
    unless trusted_port?
      control_access :enterprise,
      resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    deliver_raw STATS.hook_stats
  end

  get "/enterprise/stats/pages", operation_id: "enterprise-admin/get-pages-stats" do
    unless trusted_port?
      control_access :enterprise,
        resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    deliver_raw STATS.page_stats
  end

  get "/enterprise/stats/orgs", operation_id: "enterprise-admin/get-org-stats" do
    unless trusted_port?
      control_access :enterprise,
        resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    deliver_raw STATS.org_stats
  end

  get "/enterprise/stats/users", operation_id: "enterprise-admin/get-user-stats" do
    unless trusted_port?
      control_access :enterprise,
        resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    deliver_raw STATS.user_stats
  end

  get "/enterprise/stats/pulls", operation_id: "enterprise-admin/get-pull-request-stats" do
    unless trusted_port?
      control_access :enterprise,
        resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    deliver_raw STATS.pull_request_stats
  end

  get "/enterprise/stats/issues", operation_id: "enterprise-admin/get-issue-stats" do
    unless trusted_port?
      control_access :enterprise,
        resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    deliver_raw STATS.issue_stats
  end

  get "/enterprise/stats/milestones", operation_id: "enterprise-admin/get-milestone-stats" do
    unless trusted_port?
      control_access :enterprise,
        resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    deliver_raw STATS.milestone_stats
  end

  get "/enterprise/stats/gists", operation_id: "enterprise-admin/get-gist-stats" do
    unless trusted_port?
      control_access :enterprise,
        resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    deliver_raw STATS.gist_stats
  end

  get "/enterprise/stats/comments", operation_id: "enterprise-admin/get-comment-stats" do
    unless trusted_port?
      control_access :enterprise,
        resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    deliver_raw STATS.comment_stats
  end
end
