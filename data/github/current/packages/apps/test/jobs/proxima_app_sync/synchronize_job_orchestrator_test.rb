# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SynchronizeJobOrchestratorTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    integration = create :integration
    @app_state = ProximaAppSynchronization.create(
      dotcom_global_id: "1",
      local_app_id: integration.id,
      local_app_type: "Integration",
      fingerprint: "abc123"
    )
  end

  setup do
    GitHub.flipper[:proxima_app_synchronizations].enable
  end

  [ProximaAppHelper::FIRST_PARTY_TYPE, ProximaAppHelper::THIRD_PARTY_TYPE].each do |party_type|
    context "when #{party_type} party type" do
      context "#orchestrate" do
        test "calls syncable apps endpoint" do
          Apps::Internal::ApiHmacClient.any_instance.expects(:syncable_apps).with(sync_records: [@app_state], party_type: party_type).returns({ "apps" => [] })

          ProximaAppSync::SynchronizeJobOrchestrator.orchestrate(party_type)
        end

        test "enqueues app destroy job when app is third party type" do
          Apps::Internal::ApiHmacClient.any_instance.expects(:syncable_apps).returns({
            "apps" =>
              [{
                "global_relay_id" => @app_state.dotcom_global_id,
                "marked_for_deletion" => true
              }]
            })

          assert_enqueued_with(job: ProximaAppSync::DestroySyncedAppJob, args: [{ dotcom_global_id: @app_state.dotcom_global_id }]) do
            ProximaAppSync::SynchronizeJobOrchestrator.orchestrate(party_type)
          end
        end if party_type == ProximaAppHelper::THIRD_PARTY_TYPE

        test "does not enqueue app destroy job when app is first party type" do
          Apps::Internal::ApiHmacClient.any_instance.expects(:syncable_apps).returns({
            "apps" =>
              [{
                "global_relay_id" => @app_state.dotcom_global_id,
                "marked_for_deletion" => true
              }]
            })

          assert_no_enqueued_jobs(only: ProximaAppSync::DestroySyncedAppJob) do
            ProximaAppSync::SynchronizeJobOrchestrator.orchestrate(party_type)
          end
        end  if party_type == ProximaAppHelper::FIRST_PARTY_TYPE

        test "enqueues app create job" do
          Apps::Internal::ApiHmacClient.any_instance.expects(:syncable_apps).returns({
            "apps" =>
              [{
                "global_relay_id" => "123",
                "fingerprint" => "qwerty"
              }]
            })

          assert_enqueued_with(job: "ProximaAppSync::Create#{party_type.capitalize}PartyAppJob".constantize, args: [{ app_global_relay_id: "123" }]) do
            ProximaAppSync::SynchronizeJobOrchestrator.orchestrate(party_type)
          end
        end

        test "enqueues app update job" do
          Apps::Internal::ApiHmacClient.any_instance.expects(:syncable_apps).returns({
            "apps" =>
              [{
                "global_relay_id" => @app_state.dotcom_global_id,
                "fingerprint" => @app_state.fingerprint
              }]
            })

          assert_enqueued_with(job: "ProximaAppSync::Update#{party_type.capitalize}PartyAppJob".constantize, args: [@app_state.dotcom_global_id, @app_state.fingerprint]) do
            ProximaAppSync::SynchronizeJobOrchestrator.orchestrate(party_type)
          end
        end

        test "does not perform initial call when flipper flag is disabled" do
          GitHub.flipper[:proxima_app_synchronizations].disable
          Apps::Internal::ApiHmacClient.expects(:syncable_apps).never

          ProximaAppSync::SynchronizeJobOrchestrator.orchestrate(party_type)
        end
      end
    end
  end
end
