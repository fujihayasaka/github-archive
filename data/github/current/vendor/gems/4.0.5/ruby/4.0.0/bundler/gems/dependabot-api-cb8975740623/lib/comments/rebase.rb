# frozen_string_literal: true

module Comments
  module Rebase
    BASE_COMMIT_UNCHANGED = <<~COMMENT
      The base commit for this pull request has not changed.
    COMMENT

    CLOSED = <<~COMMENT.squish
      Looks like this PR is closed. If the branch still exists, you can re-open the PR
      and then use `@dependabot rebase` or `@dependabot recreate`. If the branch was deleted,
      Dependabot will create a new PR on the next scheduled run, or you can trigger an update
      from the Dependency graph page.
    COMMENT

    DELETED = <<~COMMENT
      The dependabot.yml entry that created this PR has been deleted so this PR can't be rebased. Please close the PR so Dependabot can create a new one with the current dependabot.yml.

    COMMENT

    MERGED = <<~COMMENT
      Looks like this PR has already been merged!
    COMMENT

    PULL_REQUEST_EDITED = <<~COMMENT
      Looks like this PR has been edited by someone other than Dependabot. That means Dependabot can't rebase it - sorry!

      If you're happy for Dependabot to recreate it from scratch, overwriting any edits, you can request `@dependabot recreate`.
    COMMENT

    SOMETHING_WENT_WRONG = <<~COMMENT
      Oh no! Something went wrong on our end. Please try again later.

      If the problem persists, please contact GitHub support for assistance 🙇
    COMMENT
  end
end
