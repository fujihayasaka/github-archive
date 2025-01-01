# typed: strict
# frozen_string_literal: true

# Performs a repository search and then kicks off MemexBatchedBulkAddJob with the resulting issue IDs.
# Expects an already created BatchedBulkAdd job status, and a search phrase to use for finding issues/PRs using
# the elasticsearch-based SearchQuery
class MemexRepositoryBulkAddInitializerJob < ApplicationJob
  queue_as :memex_repository_bulk_add_initializer

  retry_on_dirty_exit

  resolve_tenant_context do |memex_id, _rest|
    MemexProject.find_by(id: memex_id)&.resolve_tenant
  end

  RESULTS_PER_PAGE = 100

  # @param memex_id [Integer] - ID of the MemexProject to add items to
  # @param job_status_id [String] - ID of an existing MemexBatchedBulkAddJobStatus
  # @param actor_id [Integer] - ID of the User performing the action
  # @param repository_id [Integer] - ID of the Repository to search within
  # @param count [Integer] - maximum number of items to add
  # @param search_phrase [String] - fully constructed search phrase (e.g. "is:open is:issue")
  # @param request_context [Hash] - typically GitHub.context from the initializing request
  sig do
    params(
      memex_id: Integer,
      job_status_id: String,
      actor_id: Integer,
      repository_id: Integer,
      count: Integer,
      search_phrase: String,
  request_context: T.untyped,
    ).void
  end
  def perform(memex_id, job_status_id, actor_id:, repository_id:, count:, search_phrase:, request_context: {})
    memex = MemexProject.find_by(id: memex_id)
    user = User.find_by(id: actor_id)
    repository = Repository.find_by(id: repository_id)
    return unless memex && user && repository

    issues_or_pulls = []
    page = 1

    while issues_or_pulls.length < count
      query = Search::Queries::ConditionalIssueQuery.new(
        phrase: search_phrase,
        current_user: user,
        repo_id: repository.id,
        per_page: RESULTS_PER_PAGE,
        page: page,
        sort: %w[updated desc],
        fields: [],
        normalizer: lambda { |results| results.map! { |h| h["_model"] }.compact },
        context: "memex_repository_bulk_initializer_job-search",
      )

      result = query.execute
      page_results = result.take(RESULTS_PER_PAGE)
      break if page_results.empty?

      issues_or_pulls.concat(page_results)

      next_page_num = result.next_page
      break unless next_page_num
      page = T.cast(next_page_num.to_i, Integer)
    end

    issue_ids = issues_or_pulls.take(count).map do |issue_or_pull|
      if issue_or_pull.is_a?(PullRequest)
        issue_or_pull.issue&.id
      else
        issue_or_pull.id
      end
    end.compact

    if issue_ids.empty?
      status = MemexBatchedBulkAddJobStatus.find(job_status_id) rescue nil
      status&.success!
      return
    end

    MemexBatchedBulkAddJob.perform_later(
      memex.id,
      job_status_id,
      actor_id: user.id,
      item_ids: issue_ids,
      column_data: [],
      request_context: request_context,
    )
  end
end
