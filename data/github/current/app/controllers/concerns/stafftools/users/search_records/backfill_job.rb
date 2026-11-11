# typed: true
# frozen_string_literal: true

module Stafftools::Users::SearchRecords::BackfillJob
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { StafftoolsController }

  # Registry of supported backfill types. Each entry describes how to
  # construct the underlying repair job, count the records to be processed,
  # and label the resulting flash notices.
  BACKFILL_TYPES = {
    pull_requests: {
      job_class: RepairPullRequestsIndexJob,
      index: "pull-requests",
      label: "Pull Requests",
      count: ->(org_id) {
        repository_ids = Repository.where(owner_id: org_id).pluck(:id)
        PullRequest.where(repository_id: repository_ids).count
      },
    },
  }.freeze

  private

  def organization_id
    this_user.id
  end

  def backfill_config(backfill_type)
    BACKFILL_TYPES.fetch(backfill_type.to_sym)
  end

  def create_backfill_job(backfill_type)
    config = backfill_config(backfill_type)
    config[:job_class].new(
      config[:index],
      upsert_only: true,
      purge: false,
      target_scope: :organization,
      target_scope_id: organization_id,
    )
  end

  def backfill_count(backfill_type)
    backfill_config(backfill_type)[:count].call(organization_id)
  end

  def start_backfill_notice(backfill_type, workers)
    "Backfilling #{backfill_count(backfill_type)} #{backfill_plural_label(backfill_type)} with #{workers} workers ..."
  end

  def pause_backfill_notice(backfill_type)
    "Paused #{backfill_label(backfill_type)} backfill for #{this_user.display_login}"
  end

  def reset_backfill_notice(backfill_type)
    "Reset #{backfill_label(backfill_type)} backfill for #{this_user.display_login}"
  end

  def update_workers_backfill_notice(backfill_type, workers)
    "Updated #{backfill_label(backfill_type)} backfill to use #{workers} worker#{"s" unless workers == 1} for #{this_user.display_login}"
  end

  def clear_backfill_notice(backfill_type)
    "Cleared #{backfill_label(backfill_type)} backfill for #{this_user.display_login}"
  end

  def backfill_label(backfill_type)
    config = backfill_config(backfill_type)
    config[:label]
  end

  def backfill_plural_label(backfill_type)
    config = backfill_config(backfill_type)
    config[:label].downcase
  end
end
