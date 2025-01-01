# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    # GitHub::Migrator defaults to these GitHub style urls. A migration archive
    # can override the GitHub defaults by providing urls.json and using the
    # appropriate schema version.
    DefaultUrlTemplates = {
      "user"                        => "{scheme}://{host}/{user}",
      "organization"                => "{scheme}://{host}/{organization}",
      "repository"                  => "{scheme}://{host}/{owner}/{repository}",
      "team"                        => "{scheme}://{host}/orgs/{owner}/teams/{team}",
      "milestone"                   => "{scheme}://{host}/{owner}/{repository}/milestones/{milestone}",
      "issue"                       => "{scheme}://{host}/{owner}/{repository}/issues/{issue}",
      "pull_request"                => "{scheme}://{host}/{owner}/{repository}/pull/{pull_request}",
      "pull_request_review_comment" => "{scheme}://{host}/{owner}/{repository}/pull/{pull_request}/files#r{pull_request_review_comment}",
      "commit_comment"              => "{scheme}://{host}/{owner}/{repository}/commit/{commit}#commitcomment-{commit_comment}",
      "issue_comment"               => {
        "issue"        => "{scheme}://{host}/{owner}/{repository}/issues/{number}#issuecomment-{issue_comment}",
        "pull_request" => "{scheme}://{host}/{owner}/{repository}/pull/{number}#issuecomment-{issue_comment}",
      }.freeze,
      "issue_event" => {
        "issue"        => "{scheme}://{host}/{owner}/{repository}/issues/{number}#event-{event}",
        "pull_request" => "{scheme}://{host}/{owner}/{repository}/pull/{number}#event-{event}",
      }.freeze,
      "release"                     => "{scheme}://{host}/{owner}/{repository}/releases/tag/{release}",
      "label"                       => "{scheme}://{host}/{owner}/{repository}/labels/{label}",
    }.freeze
  end
end
