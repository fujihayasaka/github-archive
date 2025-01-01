# typed: true
# frozen_string_literal: true

class MemexProjectItemQueryJob < ApplicationJob
  MAX_ATTEMPTS = 5
  SUPPORTED_ACTION_JOBS = [MemexDestroyItemsJob, MemexUnarchiveItemsJob]

  queue_as :memex_project_item_query

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on JobStatus::NotFound, wait: :polynomially_longer, attempts: MAX_ATTEMPTS # will retry 4 times over 6 minutes

  # TODO: remove `only_archived_items` param once no remaining queued jobs still expect it
  def perform(job_id:, current_user_id:, memex_id:, query_string:, action_job_klass:, items_scope: :unarchived, only_archived_items: nil)
    raise ArgumentError.new("Unsupported action_job_klass '#{action_job_klass}'") unless SUPPORTED_ACTION_JOBS.include?(action_job_klass)

    current_user = User.find_by(id: current_user_id)
    memex_project = MemexProject.find_by(id: memex_id)
    return unless current_user && memex_project

    if !memex_project.viewer_can_write?(current_user)
      GitHub.logger.info(
        "Unable to query items due to insufficient permissions",
        { class_name: self.class.name, user_id: current_user_id, memex_id: memex_id }
      )
      return
    end

    job_status = JobStatus.find!(job_id)
    with_write { job_status.started! }

    query = Search::Queries::MemexProjectItemQuery.new(
      project: memex_project,
      viewer: current_user,
      items_scope: Search::Memex::Context::MemexProjectItemsScope.deserialize(items_scope),
      first: Search::Queries::MemexProjectItemQuery::MAX_PAGE_SIZE,
      query: query_string,
    )
    response = query.execute
    item_ids = response.map { |r| r.dig("_source", "database_id") }

    while response.has_next_page
      query = Search::Queries::MemexProjectItemQuery.new(
        project: memex_project,
        viewer: current_user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope.deserialize(items_scope),
        first: Search::Queries::MemexProjectItemQuery::MAX_PAGE_SIZE,
        after: response.end_cursor,
        query: query_string,
      )
      response = query.execute
      item_ids = item_ids + response.map { |r| r.dig("_source", "database_id") }
    end

    action_job_klass.perform_later(job_id, item_ids, current_user_id, memex_id)
  end
end
