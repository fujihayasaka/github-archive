# typed: strict
# frozen_string_literal: true

module ProximaAppSync
  class DestroySyncedAppJob < ApplicationJob

    queue_as :proxima_app_sync_destroy_app_job

    exempt_from_tenant_context_requirement
    retry_on_dirty_exit

    sig { params(dotcom_global_id: String).void }
    def perform(dotcom_global_id:)
      sync_record = ProximaAppSynchronization.find_by(dotcom_global_id: dotcom_global_id)
      return unless sync_record.present?
      return if first_party_app?(sync_record)

      with_write do
        destroy_sync_artifacts(sync_record)
      end
    end

    private

    sig { params(sync_record: ProximaAppSynchronization).void }
    def destroy_sync_artifacts(sync_record)
      sync_record.transaction do
        app = sync_record.local_app
        app.present? && app.destroy!

        sync_record.destroy!
      end
    end

    sig { params(sync_record: ProximaAppSynchronization).returns(T::Boolean) }
    def first_party_app?(sync_record)
      owner_id = if sync_record.local_app.is_a?(Integration)
        sync_record.local_app.owner_id
      else
        sync_record.local_app.user_id
      end

      owner_id == GitHub.first_party_apps_owner_id
    end
  end
end
