# typed: true
# frozen_string_literal: true

class IssueTriageJob < ApplicationJob
  use_primaries ApplicationRecord::IssuesPullRequests

  NUMBER_OF_PERCENTAGE_UPDATES = 30
  class IssueTriageUpdateFailed < StandardError ; end

  queue_as :issue_triage
  locked_by timeout: 15.minutes, key: ->(job) {
    # only allow a single job per user to run at a time
    job.arguments[2]
  }

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(job_id, issue_ids, current_user_id, params)
    params = params.with_indifferent_access
    current_user = User.find_by(id: current_user_id)

    # this find either a job status or a job status subscription
    status = JobStatusSubscription.find(job_id) || JobStatus.find(job_id)
    status ||= Issues::JobStatusSubscription.find(job_id)
    status ||= Issues::JobStatus.find(job_id)

    if status.nil?
      raise JobStatus::NotFound, "job status id not found in Issues::KV: #{job_id}"
    end

    remaining_issue_ids = issue_ids
    processed_issues_count = 0

    if status.is_subscription?
      # remove the completed items from the list of issues to update (if job had to be retried)
      remaining_issue_ids = issue_ids - status.completed_item_ids
      processed_issues_count = status.completed_item_ids.size
    end

    GitHub.logger.with_named_tags(
      "gh.user.id": current_user_id,
    ) do
      GitHub.logger.info("Bulk Update started", "number_of_issues": remaining_issue_ids.size)

      perform_with_deferred_indexing(status, issue_ids, remaining_issue_ids, processed_issues_count, current_user, params)
    end
    GitHub.logger.info("Bulk Update finished")
  end

  # Used for Job Status lookup
  def self.prefix
    name
  end

  private

  def perform_bulk_updates(status, issue_ids, remaining_issue_ids, processed_issues_count, current_user, params)
    return unless current_user

    itemids_by_type = { issues: [], prs: [] }

    Issue.where(id: remaining_issue_ids).each.with_index do |issue, index|
      GitHub.logger.info("Updating issue", "number_of_issues": remaining_issue_ids.size, "issue_id": issue.id, "index": index)
      current_step = processed_issues_count + (index + 1)
      percentage = ((current_step.to_f / issue_ids.size) * 100).to_i

      error_msg = update_issue(issue, current_user, params) if issue.editable_by?(current_user)

      if status.is_subscription?
        if status.percentage < percentage && percentage < 100
          set_percentage(status, percentage, issue_ids.size, current_step, issue.global_relay_id, error_msg)
        elsif error_msg.present?
          status.add_execution_error(issue.global_relay_id, error_msg)
        end
      end

      if status.is_subscription?
        status.add_completed_item_id(issue.id)
      end

      if issue.pull_request?
        itemids_by_type[:prs].push(issue.id)
      else
        itemids_by_type[:issues].push(issue.id)
      end
    end

    if add_project_ids(params).any?
      GlobalInstrumenter.instrument("memex_project_item.bulk_add", {
        actor: current_user,
        issue_ids: itemids_by_type[:issues],
        pull_request_ids: itemids_by_type[:prs],
        project_ids: add_project_ids(params).map { |id, _value| id.to_i },
        source: "ISSUE_INDEX"
      })
    end

    itemids_by_type
  end

  def perform_with_deferred_indexing(status, issue_ids, remaining_issue_ids, processed_issues_count, current_user, params)
    already_succeeded = status.success?
    status.started!
    begin
      indexing_issue_ids = T.let([], T.untyped)

      GitHub.context.push(skip_search_indexing: true) do
        itemids_by_type = perform_bulk_updates(status, issue_ids, remaining_issue_ids, processed_issues_count, current_user, params)
        indexing_issue_ids = itemids_by_type[:issues] if itemids_by_type
      end

      # On retry, all issues may already be completed but coordination was never set up
      # (crash between perform_bulk_updates and BulkIndexCoordination.setup).
      # Recover by indexing the previously completed issue IDs.
      if indexing_issue_ids.empty? && status.is_subscription? && status.completed_item_ids.any? &&
          !already_succeeded
        count_key = "#{Search::BulkIndexCoordination::REDIS_KEY_PREFIX}:count:#{status.id}"
        coordination_exists = Search::JobCoordination.redis.exists?(count_key)
        unless coordination_exists
          pr_ids = Issue.where(id: status.completed_item_ids).where.not(pull_request_id: nil).pluck(:id)
          indexing_issue_ids = status.completed_item_ids - pr_ids
          GitHub.logger.info("Deferred indexing retry recovery triggered", "job_status_id": status.id, "recovered_issue_ids": indexing_issue_ids)
        end
      end

      if indexing_issue_ids.any?
        Search::BulkIndexCoordination.setup(
          job_status_id: status.id,
          job_status_class: status.class.name,
          issue_ids: indexing_issue_ids,
        )
        indexing_issue_ids.each { |id| Search.add_to_search_index("issue", id) }
      else
        status.success!
      end
    rescue => err
      status.error!(err.message)
      raise err
    end
  end

  def set_percentage(status, percentage, total_size, index, issue_global_reay_id, error)
    if total_size < NUMBER_OF_PERCENTAGE_UPDATES + 1
      error.present? ? status.set_percentage_and_error(percentage, issue_global_reay_id, error) : status.set_percentage(percentage)
    elsif index % (total_size / NUMBER_OF_PERCENTAGE_UPDATES) == 0
      error.present? ? status.set_percentage_and_error(percentage, issue_global_reay_id, error) : status.set_percentage(percentage)
    end
  end

  sig { params(params: T::Hash[Symbol, T.untyped]).returns(T::Hash[String, Integer]) }
  def add_project_ids(params)
    return @add_project_ids if defined?(@add_project_ids)

    @add_project_ids = if params[:projects].is_a?(Hash)
      params[:projects].select { |_id, value| value == "on" }
    else
      {}
    end
  end

  sig { params(params: T::Hash[Symbol, T.untyped]).returns(T::Hash[String, Integer]) }
  def remove_project_ids(params)
    return @remove_project_ids if defined?(@remove_project_ids)

    @remove_project_ids = if params[:projects].is_a?(Hash)
      params[:projects].select { |_id, value| value == "off" }
    else
      {}
    end
  end

  def update_issue(issue, current_user, params)
    with_write do
      GitHub.context.push(actor_id: current_user.id) do
        issue.modifying_user = current_user
        old_assignees = issue.assignees.to_a

        Audit.context.push(actor_id: current_user.id) do
          # Archive/unarchive (pull requests only)
          if params.key?(:archive) && issue.pull_request?
            pull = issue.pull_request
            if params[:archive] == "true" && pull&.archivable_by?(current_user)
              pull.archive!(current_user, issue)
              return nil
            elsif params[:archive] == "false" && pull&.unarchivable_by?(current_user)
              pull.unarchive!(current_user)
              return nil
            end
          end

          # Assign state
          case params[:state]
          when "open"
            issue.reopen!(current_user) unless issue.open?
            return nil
          when "closed"
            state_reason = params[:state_reason]
            state_reason_changing = state_reason != issue.state_reason

            # completed is only supported in the API, it is not a valid state_reason in the DB
            state_reason = nil if state_reason == "completed"
            issue.close(current_user, attributes: { state_reason: state_reason }) if state_reason_changing || issue.open?
            return nil
          end

          # Assign an assignee
          if issue.assignable_by?(actor: current_user)
            if params.key?(:assignee)
              issue.assignee = User.find_by(id: params[:assignee])
            end

            if params[:assignees].is_a?(Hash)
              add_ids = params[:assignees].select { |_id, value| value == "1" }.map { |id, _value| id }
              delete_ids = params[:assignees].select { |_id, value| value == "0" }.map { |id, _value| id }

              new_assignees = old_assignees.reject { |assignee| delete_ids.include?(assignee.id.to_s) }
              new_assignees += User.where(id: add_ids)
              new_assignees = new_assignees.uniq(&:id)
              issue.assignees = new_assignees
            end

            if params[:clear_assignees].present?
              issue.assignees = []
            end
          end

          # Assign a milestone
          if issue.can_set_milestone?(current_user)
            if params.key?(:milestone)
              milestone = issue.repository.milestones.find_by_id(params[:milestone])
              issue.milestone = milestone
            end
          end

          # Assign an issue type
          if issue.can_set_type?(actor: current_user)
            if params.key?(:issue_type)
              issue_types = Issues.domain.issue_types.by_organization(issue.repository.owner_id)
              id = issue_types.find { |type| type.id.to_s == params[:issue_type].to_s }&.id
              issue.issue_type = id.present? ? IssueType.find(id) : nil
            end
          end

          # Assign labels
          if issue.labelable_by?(actor: current_user)
            if params[:labels].is_a?(Hash)
              add_ids = params[:labels].select { |_id, value| value == "1" }.map { |id, _value| id }
              delete_ids = params[:labels].select { |_id, value| value == "0" }.map { |id, _value| id }

              Issue.throttle_with_retry { issue.add_label_ids(add_ids) }
              Issue.throttle_with_retry { issue.delete_label_ids(delete_ids) }
            end
          end

          # Update projects
          if issue.triageable_by?(current_user) || issue.viewer_can_update?(current_user)
            if params[:projects].is_a?(Hash)
              issue_or_pull_request = issue.pull_request? ? issue.pull_request : issue
              if add_project_ids(params).any?
                begin
                  issue.add_to_memex_projects!(add_project_ids(params), issue_or_pull_request, current_user)
                # Rescue exceptions when a project is over the item limit and report the error
                rescue MemexProjectItem::ProjectLimitReachedError => e
                  errored_projects_ids = e.memex_projects_with_errors.map(&:id)
                  errored_projects_count = e.memex_projects_with_errors.length
                  project_item_limit = e.memex_projects_with_errors.first&.items_limit
                  return report_errors("Triaging issue #{issue.id} failed because the #{"project".pluralize(errored_projects_count)} #{errored_projects_ids.to_sentence} exceeded the item limit of #{project_item_limit}.")
                end
              end
              if remove_project_ids(params).any?
                issue.remove_from_memex_projects!(remove_project_ids(params), issue_or_pull_request, current_user)
              end
            end
          end

          begin
            removed_ids = (old_assignees.map(&:id) - issue.assignees.map(&:id))
            if removed_ids.any?
              (@copilot_domain ||= Issues::Domain::Copilot.new)
                .remove_eyes_emoji_reaction(issue: issue, removed_assignee_ids: removed_ids)
            end
            saved = Issue.throttle_with_retry { issue.save }
          rescue GitHub::Prioritizable::Context::LockedForRebalance
            return report_errors("Triaging issue #{issue.id} failed because milestone #{params[:milestone]} is locked for rebalance.")
          end

          if saved
            nil
          else
            report_errors("Triaging for issue #{issue.id} with invalid #{issue.errors.attribute_names}")
          end
        end
      end
    end
  end

  def report_errors(error_msg)
    Failbot.push(app: "github-user")
    Failbot.report(IssueTriageUpdateFailed.new(error_msg))
    error_msg
  end
end
