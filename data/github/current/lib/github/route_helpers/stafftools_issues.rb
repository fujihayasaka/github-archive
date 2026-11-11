# typed: true
# frozen_string_literal: true

module GitHub
  module RouteHelpers

    def gh_stafftools_repository_issues_path(repo)
      expand_nwo_from :stafftools_repository_issues_path, repo
    end

    def gh_stafftools_repository_issue_path(issue)
      expand_from_issue :stafftools_repository_issue_path, issue
    end

    def gh_database_stafftools_repository_issue_path(issue)
      expand_from_issue :database_stafftools_repository_issue_path, issue
    end

    private

    def expand_from_issue(helper, issue)
      repo = issue.repository
      if repo.owner && repo.name && issue.number
        send(helper, repo.owner, repo.name, issue.number)
      else
        "#"
      end
    end

  end
end
