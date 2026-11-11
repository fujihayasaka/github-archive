# typed: true
# frozen_string_literal: true

# The purpose of this job is to reconcile the state of PullRequest records
# between the database and the search index. We do this by iterating over
# PullRequest records in batches of 100. The `updated_at` timestamp of the
# each PR is compared between the database and the search index. The
# search index is then updated for any PRs where the timestamps disagree.
#
# Each repair job will process 100 pull requests. When it has reconciled
# all those pull requests it will enqueue another job. This process will
# continue until all pull requests have been processed.
#
# To make this whole process faster, multiple repair jobs can be enqueued.
# The current offset into the pull requests table is stored in redis.
# Access to this value is coordinated via a shared mutex. Don't spin up
# too many repair jobs otherwise you'll kill the database or the search
# index or both.
class RepairPullRequestsIndexJob < Elastomer::RepairJob
  queue_as :index_bulk

  reconcile "pull_request",
    named_scopes: {
      repository: -> (id) { PullRequest.where(repository_id: id) },
      organization: -> (id) { PullRequest.where(repository_id: Repository.where(owner_id: id).pluck(:id)) },
      user_created: -> (id) { PullRequest.where(user_id: id) },
      user_reviewed: -> (id) {
        PullRequest.joins(:reviews)
          .where(pull_request_reviews: { user_id: id })
          .distinct
      },
      user_commented: -> (id) {
        PullRequest.joins(:issue)
          .joins("INNER JOIN issue_comments ON issue_comments.issue_id = issues.id")
          .where(issue_comments: { user_id: id })
          .distinct
      },
    },
    fields: %w[updated_at],
    limit: 100,
    reject: :spammy?,
    accept: [:base_user, :head_user],
    include: [
      :repository, :user, :review_comments,
      :base_repository, :head_repository, :base_user, :head_user,
      { issue: [:repository, { assignments: :assignee }, { comments: :user }, :labels] }
    ],
    adapter_args: { skip_commit_info_on_failure: true }

  PROD_CONSOLE_BLOCKED_MESSAGE = <<~BLOCKED_MESSAGE

    ------RepairPullRequestsIndexJob BLOCKED------

    This job cannot be executed via a prod console.
    PRs can be re-indexed or backfilled in Stafftools: https://admin.github.com/stafftools/repositories/<OWNER>/<REPO>/search
    Visit these docs for more info: https://thehub.github.com/epd/engineering/products-and-services/dotcom/search/manually-reindexing-repo-issues-prs/

    ------RepairPullRequestsIndexJob BLOCKED------

  BLOCKED_MESSAGE

  def start(count = 1)
    if Rails.env.production? && ENV["GH_CONSOLE"] == "1" # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      puts PROD_CONSOLE_BLOCKED_MESSAGE
      return
    end

    super
  end

  # Override to make the job safe by default - only update/insert documents,
  # don't delete them from the index unless explicitly set to false.
  def upsert_only? # rubocop:disable GitHub/ControllersShouldUseMemoizeForMemoization
    @upsert_only ||= job_opts.fetch(:upsert_only, true)
  end
end
