# typed: true
# frozen_string_literal: true

# The purpose of this job is to reconcile the state of PullRequest records
# between the database and the search index. We do this by iterating over
# PullRequest records in batches of 500. The `updated_at` timestamp of the
# each PR is compared between the database and the search index. The
# search index is then updated for any PRs where the timestamps disagree.
#
# Each repair job will process 500 pull requests. When it has reconciled
# all those pull requests it wil enqueue another job. Thes process will
# continue until all pull requests have been processed.
#
# To make this whole process faster, multiple repair jobs can be enqueued.
# The current offest into the pull requetss table is stored in redis.
# Access to this value is coordinated via a shared mutex. Don't spin up
# too many repair jobs otherwise you'll kill the database or the search
# index or both.
class RepairPullRequestsIndexJob < Elastomer::RepairJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :index_bulk

  reconcile "pull_request",
    fields: %w[updated_at],
    limit: 500,
    reject: :spammy?,
    accept: [:base_user, :head_user],
    include: [
      :repository, :user, :review_comments,
      :base_repository, :head_repository, :base_user, :head_user,
      { issue: [:repository, { assignments: :assignee }, { comments: :user }, :labels] }
    ],
    adapter_args: { skip_commit_info_on_failure: true }
end
