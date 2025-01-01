# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class HydroDependabotAlertRevisionJobTest < GitHub::TestCase
    include HydroMessageJobTestHelpers
    include JobTestHelper
    include DogstatsTestHelpers

    Event = ::Hydro::Schemas::Github::SecurityAlerts::V1::RepositoryVulnerabilityAlertLifecycleEvent

    fixtures do
      @queue = HydroDependabotAlertRevisionJob.queue_name
      @schema = "github.security_alerts.v1.RepositoryVulnerabilityAlertLifecycleEvent"
      @user = create :user
      @org = create :business_plus_organization, admin: @user
      @repo = create :repository, owner: @org

      vulnerable_version_range = create(:vulnerable_version_range, affects: "react", fixed_in: "2", ecosystem: "npm")
      vulnerability = create(:vulnerability, severity: "high")
      @alert = create(:repository_vulnerability_alert,
        vulnerable_manifest_path: "package.json",
        vulnerable_version_range:,
        vulnerability:,
        repository: @repo,
      )
    end

    setup do
      TenantValidationHelper.stubs(:should_handle_dependabot_alert_events?).returns(true)
    end

    context "when repository is not found" do
      test "raises error if the event is not a resolve event" do
        HydroDependabotAlertRevisionJob.any_instance.expects(:retry).once.with(
          responds_with(
            :message,
            "Couldn't find Repository with 'id'=0",
          ),
          delay: 2.0,
        )

        perform_hydro_message_job(
          event_message(action: "create", repository_id: 0),
          schema: @schema,
          queue: @queue,
        )

        assert_empty DependabotAlertRevision.all.to_a
      end

      test "raises error if the alert for the event exists" do
        RepositoryVulnerabilityAlert.expects(:exists?).with(id: @alert.id).returns(true)
        HydroDependabotAlertRevisionJob.any_instance.expects(:retry).once.with(
          responds_with(
            :message,
            "Couldn't find Repository with 'id'=0",
          ),
          delay: 2.0,
        )

        perform_hydro_message_job(
          event_message(action: "resolve", repository_id: 0),
          schema: @schema,
          queue: @queue,
        )

        assert_empty DependabotAlertRevision.all.to_a
      end

      test "returns if the event is a resolve event and the alert does not exist" do
        RepositoryVulnerabilityAlert.expects(:exists?).with(id: @alert.id).returns(false)
        HydroDependabotAlertRevisionJob.any_instance.expects(:retry).never

        perform_hydro_message_job(
          event_message(action: "resolve", repository_id: 0),
          schema: @schema,
          queue: @queue,
        )

        assert_empty DependabotAlertRevision.all.to_a
      end

      test "deletes alert data if alerts being withdrawn" do
        HydroDependabotAlertRevisionJob.any_instance.expects(:retry).never

        create(:soa_dependabot_alert_revision, repository_id: 0, alert_number: @alert.number)
        assert_equal 1, DependabotAlertRevision.count

        perform_hydro_message_job(
          event_message(action: "withdraw", repository_id: 0),
          schema: @schema,
          queue: @queue,
        )

        assert_equal 0, DependabotAlertRevision.count
        assert_dogstats_count 1, "security_overview_analytics.dependabot_alert_revisions.deleted"
      end
    end

    test "returns if job shouldn't handle this Dependabot alert event" do
      TenantValidationHelper.stubs(:should_handle_dependabot_alert_events?).returns(false)

      perform_hydro_message_job(event_message, schema: @schema, queue: @queue)

      assert_empty DependabotAlertRevision.all.to_a
    end

    context "when alerts being withdrawn" do
      test "delete alert revisions on withdraw event" do
        create(:soa_dependabot_alert_revision, repository: @repo, alert_number: @alert.number)
        assert_equal 1, DependabotAlertRevision.count

        assert_query_count_per_table({
          soa_dependabot_alert_revisions: 2, # 1 SELECT check for exists, 1 DELETE
        }) do
          perform_hydro_message_job(withdraw_event_message, schema: @schema, queue: @queue)
        end

        assert_equal 0, DependabotAlertRevision.count
        assert_dogstats_count 1, "security_overview_analytics.dependabot_alert_revisions.deleted"
      end

      test "returns if alert is not tracked in revisions table" do
        assert_equal 0, DependabotAlertRevision.count

        assert_query_count_per_table({
          soa_dependabot_alert_revisions: 1, # 1 SELECT check for exists
        }) do
          perform_hydro_message_job(withdraw_event_message, schema: @schema, queue: @queue)
        end

        assert_equal 0, DependabotAlertRevision.count
        refute_dogstats_count "security_overview_analytics.dependabot_alert_revisions.deleted"
      end
    end

    test "calls #{DependabotAlertRevision}.upsert_revision with args generated from event payload" do
      t = Time.now.utc

      DependabotAlertRevision.expects(:upsert_revision).with(
        DependabotAlertRevision::UpdatePayload.new(
          alert_resolved: false,
          alert_resolved_at: nil,
          alert_severity: :LOW,
          dependency_scope: :DEVELOPMENT,
          ghsa_id: "GHSA-ABCD-ABCD-ABCD",
          package_name: "pkg",
          ecosystem: "eco",
          alert_created_at: t,
          alert_updated_at: t,
        ),
        repository_id: @repo.id,
        alert_number: @alert.number,
        date_id: Date.id_from_time(@alert.created_at),
      )

      perform_hydro_message_job(event_message(
        repository_id: @alert.repository_id,
        repository_vulnerability_alert_id: @alert.id,
        repository_vulnerability_alert_number: @alert.number,
        created_at: t,
        updated_at: t,
        last_state_change_at: t,
        state: :OPEN,
        severity: :LOW,
        ghsa_id: "GHSA-ABCD-ABCD-ABCD",
        dependency_scope: :DEVELOPMENT,
        package_name: "pkg",
        ecosystem: "eco",
      ), schema: @schema, queue: @queue)
    end

    context "on multi tenant enterprise" do
      test "resolves tenant context and performs for alert from the same tenant" do
        on_multi_tenant_enterprise do
          mt_user = create(:emu)
          mt_business = mt_user.enterprise_managed_business
          GitHub::CurrentTenant.set(mt_business)
          mt_org = create :enterprise_linked_organization, :with_org_namespacing, business: mt_business, admin: mt_user
          mt_repo = create(:private_repository, owner: mt_org)

          vulnerable_version_range = create(:vulnerable_version_range, affects: "react", fixed_in: "2", ecosystem: "npm")
          vulnerability = create(:vulnerability, severity: "high")
          mt_alert = create(:repository_vulnerability_alert,
            vulnerable_manifest_path: "package.json",
            vulnerable_version_range:,
            vulnerability:,
            repository: mt_repo,
          )

          # Simulate no tenant being set
          GitHub::CurrentTenant.remove
          assert_nil GitHub::CurrentTenant.get
          refute_predicate GitHub::CurrentTenant, :unscoped?

          t = Time.now.utc
          Repositories::Public.expects(:resolve_tenant).once.with(id: mt_repo.id).returns(mt_business)
          DependabotAlertRevision.expects(:upsert_revision).with(
            DependabotAlertRevision::UpdatePayload.new(
              alert_resolved: false,
              alert_resolved_at: nil,
              alert_severity: :LOW,
              dependency_scope: :DEVELOPMENT,
              ghsa_id: "GHSA-ABCD-ABCD-ABCD",
              package_name: "pkg",
              ecosystem: "eco",
              alert_created_at: t,
              alert_updated_at: t,
            ),
            repository_id: mt_repo.id,
            alert_number: mt_alert.number,
            date_id: Date.id_from_time(mt_alert.created_at),
          )

          perform_hydro_message_job(event_message(
            repository_id: mt_alert.repository_id,
            repository_vulnerability_alert_id: mt_alert.id,
            repository_vulnerability_alert_number: mt_alert.number,
            created_at: t,
            updated_at: t,
            last_state_change_at: t,
            state: :OPEN,
            severity: :LOW,
            ghsa_id: "GHSA-ABCD-ABCD-ABCD",
            dependency_scope: :DEVELOPMENT,
            package_name: "pkg",
            ecosystem: "eco",
          ), schema: @schema, queue: @queue)
        end
      end
    end

    private

    def event_message(
      action: "create",
      repository_id: @alert.repository_id,
      repository_vulnerability_alert_id: @alert.id,
      repository_vulnerability_alert_number: @alert.number,
      created_at: @alert.created_at,
      updated_at: @alert.updated_at,
      last_state_change_at: @alert.last_state_change_at,
      state: @alert.state.upcase.to_sym,
      severity: @alert.severity.upcase.to_sym,
      ghsa_id: @alert.vulnerability.ghsa_id,
      dependency_scope: @alert.dependency_scope.upcase.to_sym,
      package_name: @alert.package_name,
      ecosystem: @alert.ecosystem,
      last_state_change_reason: Event::LastStateChangeReason.lookup(Event::LastStateChangeReason::NO_REASON)
    )
      {
        action:,
        repository_id:,
        repository_vulnerability_alert_id:,
        repository_vulnerability_alert_number:,
        created_at:,
        updated_at:,
        last_state_change_at:,
        state:,
        severity:,
        ghsa_id:,
        dependency_scope:,
        package_name:,
        ecosystem:,
        last_state_change_reason:
      }
    end

    def withdraw_event_message(
      repository_id: @alert.repository_id,
      repository_vulnerability_alert_id: @alert.id,
      repository_vulnerability_alert_number: @alert.number
    )
      {
        action: "withdraw",
        repository_id:,
        repository_vulnerability_alert_id:,
        repository_vulnerability_alert_number:,
        created_at: @alert.created_at,
        updated_at: @alert.updated_at,
      }
    end
  end
end
