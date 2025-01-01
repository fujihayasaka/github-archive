# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    GitLabUrlTemplates = {
      "user" => "{scheme}://{+host}{/segments*}/{user}",
      "organization" => "{scheme}://{+host}/groups/{organization}",
      "team" => "{scheme}://{+host}/groups/{owner}/teams/{team}",
      "repository" => "{scheme}://{+host}/{owner}/{repository}",
      "protected_branch" => "{scheme}://{+host}/{owner}/{repository}/protected_branches/{protected_branch}",
      "milestone" => "{scheme}://{+host}/{owner}/{repository}/milestones/{milestone}",
      "issue" => "{scheme}://{+host}/{owner}/{repository}/issues/{issue}",
      "pull_request" => "{scheme}://{+host}/{owner}/{repository}/merge_requests/{pull_request}",
      "pull_request_review_comment" => "{scheme}://{+host}/{owner}/{repository}/merge_requests/{pull_request}/diffs#note_{pull_request_review_comment}",
      "commit_comment" => "{scheme}://{+host}/{owner}/{repository}/commit/{commit}#note_{commit_comment}",
      "issue_comment" =>  {
        "issue" => "{scheme}://{+host}/{owner}/{repository}/issues/{number}#note_{issue_comment}",
        "pull_request" => "{scheme}://{+host}/{owner}/{repository}/merge_requests/{number}#note_{issue_comment}",
      },
      "release" => "{scheme}://{+host}/{owner}/{repository}/tags/{release}",
      "label" => "{scheme}://{+host}/{owner}/{repository}/labels#/{label}",
    }.freeze

    BitBucketServerUrlTemplates = {
      "user"                        => "{scheme}://{+host}/{segment}/{user}",
      "organization"                => "{scheme}://{+host}/projects/{organization}",
      "team"                        => "{scheme}://{+host}/admin/groups/view?name={+team}{#owner}",
      "repository"                  => "{scheme}://{+host}/{segment}/{owner}/repos/{repository}",
      "issue_comment"               => {
        "pull_request" => "{scheme}://{+host}/{segment}/{owner}/repos/{repository}/pull-requests/{number}/overview?commentId={issue_comment}",
      },
      "issue_event" => {
        "pull_request" => "{scheme}://{+host}/{segment}/{owner}/repos/{repository}/pull-requests/{number}#event-{event}",
      },
      "pull_request"                => "{scheme}://{+host}/{segment}/{owner}/repos/{repository}/pull-requests/{pull_request}",
      "pull_request_review_comment" => "{scheme}://{+host}/{segment}/{owner}/repos/{repository}/pull-requests/{pull_request}/overview?commentId={pull_request_review_comment}#r{pull_request_review_comment}",
      "commit_comment"              => "{scheme}://{+host}/{segment}/{owner}/repos/{repository}/commits/{commit}?commentId={commit_comment}#commitcomment-{commit_comment}",
      "release"                     => "{scheme}://{+host}/{segment}/{owner}/repos/{repository}/browse?at=refs%2Ftags%2F{+release}",
      "protected_branch"            => "{scheme}://{+host}/plugins/servlet/branch-permissions/{owner}/{repository}{#protected_branch}",
    }.freeze

    BitBucketServerUrlTemplatesReleasesNotEncoded = {
      "user"                        => "{scheme}://{+host}/{segment}/{user}",
      "organization"                => "{scheme}://{+host}/projects/{organization}",
      "team"                        => "{scheme}://{+host}/admin/groups/view?name={+team}{#owner}",
      "repository"                  => "{scheme}://{+host}/{segment}/{owner}/repos/{repository}",
      "issue_comment"               => {
        "pull_request" => "{scheme}://{+host}/{segment}/{owner}/repos/{repository}/pull-requests/{number}/overview?commentId={issue_comment}",
      },
      "issue_event" => {
        "pull_request" => "{scheme}://{+host}/{segment}/{owner}/repos/{repository}/pull-requests/{number}#event-{event}",
      },
      "pull_request"                => "{scheme}://{+host}/{segment}/{owner}/repos/{repository}/pull-requests/{pull_request}",
      "pull_request_review_comment" => "{scheme}://{+host}/{segment}/{owner}/repos/{repository}/pull-requests/{pull_request}/overview?commentId={pull_request_review_comment}#r{pull_request_review_comment}",
      "commit_comment"              => "{scheme}://{+host}/{segment}/{owner}/repos/{repository}/commits/{commit}?commentId={commit_comment}#commitcomment-{commit_comment}",
      "release"                     => "{scheme}://{+host}/{segment}/{owner}/repos/{repository}/browse?at=refs/tags/{release}",
      "protected_branch"            => "{scheme}://{+host}/plugins/servlet/branch-permissions/{owner}/{repository}{#protected_branch}",
    }.freeze
  end
end
