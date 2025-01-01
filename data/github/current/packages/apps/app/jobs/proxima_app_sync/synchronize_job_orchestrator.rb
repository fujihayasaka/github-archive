# typed: strict
# frozen_string_literal: true

# This job kicks off syncing 1st party apps from dotcom
# to a Proxima stamp
module ProximaAppSync
  class SynchronizeJobOrchestrator

    # This method is responsible for kicking off the jobs that either create or update an app that
    # requires syncing.
    sig { params(party_type: String).void }
    def self.orchestrate(party_type)
      raise "Invalid party type" unless [ProximaAppHelper::FIRST_PARTY_TYPE, ProximaAppHelper::THIRD_PARTY_TYPE].include?(party_type)

      client = Apps::Privileged::ApiHmacClient.new
      return unless client.ready?

      sync_records = ProximaAppSynchronization.all.find_all do |sync_record|
        sync_record.party_type == party_type
      end

      response = client.syncable_apps(sync_records: sync_records, party_type: party_type)

      response["apps"].each do |dotcom_app_state|
        global_id = dotcom_app_state["global_relay_id"]
        sync_record = ProximaAppSynchronization.find_by(dotcom_global_id: global_id)

        if should_delete_local_app?(dotcom_app_state, sync_record, party_type)
          ProximaAppSync::DestroySyncedAppJob.perform_later(dotcom_global_id: global_id)
        elsif sync_record.present?
          update_job = "ProximaAppSync::Update#{party_type.capitalize}PartyAppJob".constantize
          update_job.perform_later(global_id, dotcom_app_state["fingerprint"])
        else
          create_job = "ProximaAppSync::Create#{party_type.capitalize}PartyAppJob".constantize
          create_job.perform_later(app_global_relay_id: global_id)
        end
      end
    end

    sig { params(dotcom_app_state: T::Hash[String, T.untyped], sync_record: T.nilable(ProximaAppSynchronization), party_type: String).returns(T::Boolean) }
    def self.should_delete_local_app?(dotcom_app_state, sync_record, party_type)
      # call can_delete? as well on the app
      !!(sync_record.present? && dotcom_app_state["marked_for_deletion"].present? && party_type == ProximaAppHelper::THIRD_PARTY_TYPE)
    end
    private_class_method :should_delete_local_app?
  end
end
