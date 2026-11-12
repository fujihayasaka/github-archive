# frozen_string_literal: true

module Comments
  module Rebase
    BASE_COMMIT_UNCHANGED = <<~COMMENT
      The base commit for this pull request has not changed.
    COMMENT

    CLOSED = <<~COMMENT
      Looks like this PR is closed. If you re-open it, I'll rebase it, as long as no-one else has edited it.
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
