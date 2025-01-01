# typed: true
# frozen_string_literal: true

class MemexBulkAddJob < ApplicationJob
  BATCH_SIZE = 10
  MAX_ATTEMPTS = 5

  queue_as :memex_bulk_add
  retry_on_dirty_exit
  retry_on JobStatus::NotFound, wait: :polynomially_longer, attempts: MAX_ATTEMPTS # will retry 4 times over 6 minutes

  resolve_tenant_context do |_job_id, _issues_or_pulls, _current_user_id, memex_id, _columns_data|
    MemexProject.find_by(id: memex_id)&.resolve_tenant
  end

  def perform(job_id, issues_or_pulls, current_user_id, memex_id, columns_data = [])
    current_user = User.find_by(id: current_user_id)
    memex_project = MemexProject.find_by(id: memex_id)
    return unless current_user && memex_project
    return unless memex_project.viewer_can_write?(current_user)

    status = JobStatus.find!(job_id)

    status.track do
      issue_or_pulls_promises = issues_or_pulls.map do |item|
        item.async_readable_by?(current_user).then do |readable|
          next nil unless readable

          # we're unwrapping here just for the sake of permissions checks
          issue = item.is_a?(PullRequest) ? item.issue : item

          columns_permissions_promises = columns_data.map do |c|
            column_data_type = c[:column]&.data_type&.to_sym
            next Promise.resolve(true) if !c[:column]&.special_type?
            case column_data_type
            when :assignees
              next issue.async_assignable_by?(actor: current_user)
            when :milestone
              next issue.async_can_set_milestone?(current_user)
            when :labels
              next issue.async_labelable_by?(actor: current_user)
            when :parent_issue
              next issue.can_add_sub_issue?(actor: current_user, parent_issue_id: c[:value])
            else
              next Promise.resolve(false)
            end
          end

          next Promise.all(columns_permissions_promises).then do |permissions_results|
            if permissions_results.all?
              # We need to return item (either a pull or an issue) in order for it to be rendered correctly
              item
            else
              nil
            end
          end
        end
      end

      filtered_issues_or_pulls = Promise.all(issue_or_pulls_promises).sync.compact

      filtered_issues_or_pulls.each_slice(BATCH_SIZE) do |batch|
        MemexProject.throttle do
          batch.each do |issue|
            item = memex_project.build_item(issue_or_pull: issue, creator: current_user)
            begin
              with_write do
                memex_project.save_with_priority!(item, **{ position: :bottom })
                columns_data.each do |column|
                  item.set_column_value(column[:column], column[:value], current_user)
                end
              end
            rescue ActiveRecord::RecordInvalid
              item_duplicated = item.errors.of_kind?(:content_id, :taken)
              if item_duplicated
                archived_item = MemexProjectItem.where(
                  repository_id: item.content.repository_id,
                  content: item.content,
                  memex_project: memex_project,
                ).archived.first

                with_write do
                  archived_item.unarchive!
                end if archived_item
              end
            end
          end
        end
      end
    end
  end
end
