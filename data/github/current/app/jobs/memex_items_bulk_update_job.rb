# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class MemexItemsBulkUpdateJob < ApplicationJob
  include BaseHelpers::Helpers

  queue_as :memex_items_bulk_update

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  around_perform do |job, block|
    args_hash = job.arguments.first
    user = args_hash[:user]

    if GitHub.flipper[:memex_retry_update_bulk_record_not_unique].enabled?(user)
      retry_on_find_or_create_error(&block)
    else
      block.call
    end
  end

  sig { returns(T.nilable(String)) }
  def self.prefix
    name
  end

  sig { returns(Memex::JobStatus) }
  def self.create_job_status
    id = "#{prefix}:#{SecureRandom.uuid}"
    Memex::JobStatus.create(id:)
  end

  sig do
    params(
      job_id: T.any(String, Integer),
      item_ids: T::Array[T.any(String, Integer)],
      params: T.any(ActionController::Parameters, T::Hash[T.any(String, Symbol), T.untyped]),
      memex_project: MemexProject,
      user: User
    ).void
  end
  def perform(job_id:, item_ids:, params:, memex_project:, user:)
    return if item_ids.blank?

    GitHub.context.push(actor_id: user.id) if user
    job_status = Memex::JobStatus.find!(job_id)

    job_status.track do
      requests = params[:memex_project_items].map do |update_params|
        MemexProjectItem::BulkUpdater::UpdateRequest.build(update_params)
      end

      MemexProjectItem::BulkUpdater.perform(requests:, memex_project:, user:)
    end
  end
end
