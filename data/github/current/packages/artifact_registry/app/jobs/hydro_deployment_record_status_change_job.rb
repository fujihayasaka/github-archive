# typed: strict
# frozen_string_literal: true

class HydroDeploymentRecordStatusChangeJob < ApplicationJob
  queue_as :hydro_deployment_record_status_change_job
  retry_on_dirty_exit

  sig { params(records: T::Hash[Symbol, T::Array[T::Hash[Symbol, T.untyped]]]).void }
  def perform(records)
    set_records = records[:set]
    if set_records.present?
      set_records.each do |record|
        send_hydro_message_for_deployment_record(record)
      end
    end

    decommissioned_records = records[:decommissioned]
    if decommissioned_records.present?
      decommissioned_records.each do |record|
        ArtifactRegistryHydroMessageManager.send_hydro_message_for_deployment_record_by_event(ArtifactRegistryHydroMessageManager::HYDRO_EVENT_DELETE_DEPLOYMENT_RECORD, record)
      end
    end
  end

  protected

  sig { params(record: T::Hash[Symbol, T.untyped]).void }
  def send_hydro_message_for_deployment_record(record)
    ArtifactRegistryHydroMessageManager.send_hydro_message_for_deployment_record(record)
  end
end
