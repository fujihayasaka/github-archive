# typed: true
# frozen_string_literal: true

module GitHub
  module RouteHelpers
    def gh_issues_created_by_path(repo, args)
      T.bind(self, T.untyped)
      if repo
        issues_created_by_path(repo.owner_display_login, repo, args)
      else
        all_issues_path
      end
    end

    def gh_user_pull_requests_path(repo, args)
      T.bind(self, T.untyped)
      if repo
        user_pull_requests_path(repo.owner_display_login, repo, args)
      else
        all_pulls_path
      end
    end

    def gh_issues_assigned_path(repo, args)
      T.bind(self, T.untyped)
      if repo
        issues_assigned_path(repo.owner_display_login, repo, args)
      else
        all_issues_assigned_path
      end
    end

    def gh_pulls_assigned_path(repo, args)
      T.bind(self, T.untyped)
      if repo
        pulls_assigned_path(repo.owner_display_login, repo, args)
      else
        all_pulls_assigned_path
      end
    end

    def gh_issues_mentioned_path(repo, args)
      T.bind(self, T.untyped)
      if repo
        issues_mentioned_path(repo.owner_display_login, repo, args)
      else
        all_issues_mentioned_path
      end
    end

    def gh_pulls_mentioned_path(repo, args)
      T.bind(self, T.untyped)
      if repo
        pulls_mentioned_path(repo.owner_display_login, repo, args)
      else
        all_pulls_mentioned_path
      end
    end

    def gh_pulls_review_requested_path(repo, args)
      T.bind(self, T.untyped)
      if repo
        pulls_review_requested_path(repo.owner_display_login, repo, args)
      else
        all_pulls_review_requested_path
      end
    end
  end
end
