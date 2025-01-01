# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class HydroSecretScanningAlertValidityEventsJobTest < GitHub::TestCase
    include HydroMessageJobTestHelpers
    include JobTestHelper
    include DogstatsTestHelpers

    SecretScanningAlert = ::GitHub::Proto::SecretScanning::Metrics::V1::Alert
    SecretScanningAlertResolution = ::GitHub::Proto::SecretScanning::Types::V1::TokenResolution
    SecretScanningTokenValidity = ::GitHub::Proto::SecretScanning::Types::V1::TokenValidity

    EventPayload = ::Hydro::Schemas::TokenScanningService::V0::AlertEvents
    AlertEvent = ::Hydro::Schemas::TokenScanningService::V0::AlertEvents::AlertEvent
    EventTypes = ::Hydro::Schemas::TokenScanningService::V0::AlertEvents::AlertEvent::EventType

    fixtures do
      @queue = HydroSecretScanningAlertValidityEventsJob.queue_name
      @schema = "hydro.schemas.token_scanning_service.v0.AlertEvents"
      @user = create :user
      @org = create :business_plus_organization, admin: @user
      @repo = create :repository, owner: @org
    end

    setup do
      TenantValidationHelper.stubs(:should_handle_secret_scanning_alert_events?).returns(true)
    end

    test "returns if event is not supported" do
      perform_hydro_message_job(
        event_message(repository_id: @repo.id, alert_number: 1, event: :ALERT_CREATED),
        schema: @schema,
        queue: @queue,
      )

      assert_dogstats_increment 1, "security_overview_analytics.secret_scanning_alert_validity_event.skipped", tags: ["reason:unsupported_event"]
    end

    test "raises error if repository is not found" do
      HydroSecretScanningAlertValidityEventsJob.any_instance.expects(:retry).once.with(
        responds_with(
          :message,
          "Couldn't find Repository with 'id'=-1",
        ),
        delay: 2.0,
      )

      perform_hydro_message_job(
        event_message(repository_id: -1, alert_number: 1),
        schema: @schema,
        queue: @queue,
      )
    end

    test "returns if repository is deleted" do
      ::Repository.any_instance.stubs(:deleted?).returns(true)

      perform_hydro_message_job(
        event_message(repository_id: @repo.id, alert_number: 1),
        schema: @schema,
        queue: @queue,
      )

      assert_dogstats_increment 1, "security_overview_analytics.secret_scanning_alert_validity_event.skipped", tags: ["reason:repository_deleted"]
    end

    test "returns if tenant is not in scope" do
      TenantValidationHelper.stubs(:should_handle_secret_scanning_alert_events?).returns(false)

      perform_hydro_message_job(
        event_message(repository_id: @repo.id, alert_number: 1),
        schema: @schema,
        queue: @queue,
      )

      assert_dogstats_increment 1, "security_overview_analytics.secret_scanning_alert_validity_event.skipped", tags: ["reason:tenant_not_in_scope"]
    end

    test "calls #{SecretScanningAlertRevision}.upsert_revision_with_fields with fields that need updating" do
      Timecop.freeze do
        t = Time.now.utc

        SecretScanningAlertRevision.expects(:upsert_revision_with_fields).with(
          {
            alert_validity: SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE,
            alert_updated_at: t,
          },
          repository_id: @repo.id,
          alert_number: 1,
          date_id: Date.id_from_time(t)
        )

        perform_hydro_message_job(
          event_message(repository_id: @repo.id, alert_number: 1),
          schema: @schema,
          queue: @queue,
        )

        assert_dogstats_distribution 1, "security_overview_analytics.updated.dist"
      end
    end

    def event_message(repository_id:, alert_number:, event: :ALERT_VALIDATED, token_validity: :TOKEN_VALIDITY_ACTIVE)
      alert_event = { alert_number:, token_validity:, event: }
      {
        repository_id:,
        events: [alert_event]
      }
    end
  end
end
