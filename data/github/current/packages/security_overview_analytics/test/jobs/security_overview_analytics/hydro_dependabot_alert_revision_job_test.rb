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
      @vulnerability = create(:vulnerability, severity: "high")
      @alert = create(:repository_vulnerability_alert,
        vulnerable_manifest_path: "package.json",
        vulnerable_version_range:,
        vulnerability: @vulnerability,
        repository: @repo,
      )
    end

    setup do
      TenantValidationHelper.stubs(:should_handle_dependabot_alert_events?).returns(true)
      FeatureFlagHelper.stubs(:instrument_vulnerability_update_events?).returns(false)
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

    test "does nothing and returns if it's an unsupported action" do
      HydroDependabotAlertRevisionJob.any_instance.expects(:retry).never

      assert_query_count_per_table({
        soa_dependabot_alert_revisions: 0,
      }) do
        perform_hydro_message_job(
          event_message(action: "foo", repository_id: @repo.id),
          schema: @schema,
          queue: @queue,
        )
      end

      assert_empty DependabotAlertRevision.all.to_a
      assert_dogstats_increment("security_overview_analytics.dependabot_alert_revisions.skipped", tags: ["reason:action_not_supported"])
    end

    context "when a vulnerability update event is received" do
      test "updates severity for all revisions with repo id and alert number on severity change and if feature flag is on" do
        FeatureFlagHelper.stubs(:instrument_vulnerability_update_events?).returns(true)

        repo_metadata = create(:soa_repository, repository: @repo)

        date = create(:security_overview_analytics_date, date_value: Time.now.utc)
        create(:soa_dependabot_alert_revision, date_id: 20240101, next_revision_date_id: 20240102, repository_metadata: repo_metadata, alert_number: 101, alert_severity: @vulnerability.severity)
        create(:soa_dependabot_alert_revision, date_id: 20240102, next_revision_date_id: 99991231, repository_metadata: repo_metadata, alert_number: 101, alert_severity: @vulnerability.severity)
        # This one won't get updated because it's a different alert number
        create(:soa_dependabot_alert_revision, date:, repository_metadata: repo_metadata, alert_number: 102, alert_severity: @vulnerability.severity)

        assert_equal 3, DependabotAlertRevision.where(alert_severity: @vulnerability.severity).count
        UpdateFeatureStatusSummaryJob.expects(:enqueue).once

        assert_query_count_per_table({
          soa_dependabot_alert_revisions: 2, # 1 SELECT check for exists, 1 SELECT for update
        }) do
          perform_hydro_message_job(
            event_message(action: "severity_change", repository_id: @repo.id, repository_vulnerability_alert_number: 101, severity: "low"),
            schema: @schema,
            queue: @queue,
          )
        end

        assert_equal 1, DependabotAlertRevision.where(alert_severity: @vulnerability.severity).count
        assert_equal 2, DependabotAlertRevision.where(alert_severity: "low").count
        assert_dogstats_count 1, "security_overview_analytics.dependabot_alert_revisions.severities_updated"
      end

      test "does nothing if there is no matching repo id and alert number in the revisions table" do
        FeatureFlagHelper.stubs(:instrument_vulnerability_update_events?).returns(true)

        repo2 = create :repository, owner: @org
        repo_metadata = create(:soa_repository, repository: @repo)
        repo2_metadata = create(:soa_repository, repository: repo2)
        empty_repo = create :repository, owner: @org

        date = create(:security_overview_analytics_date, date_value: Time.now.utc)
        create(:soa_dependabot_alert_revision, date:, repository_metadata: repo_metadata, alert_number: 101, ghsa_id: @vulnerability.ghsa_id, alert_severity: @vulnerability.severity)
        create(:soa_dependabot_alert_revision, date:, repository_metadata: repo2_metadata, alert_number: 102, ghsa_id: @vulnerability.ghsa_id, alert_severity: @vulnerability.severity)
        create(:soa_dependabot_alert_revision, date:, repository_metadata: repo2_metadata, alert_number: 103, ghsa_id: @vulnerability.ghsa_id, alert_severity: @vulnerability.severity)

        assert_equal 3, DependabotAlertRevision.where(alert_severity: @vulnerability.severity).count

        assert_query_count_per_table({
          soa_dependabot_alert_revisions: 1, # 1 SELECT check for exists
        }) do
          perform_hydro_message_job(
            event_message(action: "severity_change", repository_id: empty_repo.id, repository_vulnerability_alert_number: 101, severity: "low"),
            schema: @schema,
            queue: @queue,
          )
        end

        assert_equal 3, DependabotAlertRevision.where(alert_severity: @vulnerability.severity).count
        assert_equal 0, DependabotAlertRevision.where(alert_severity: "low").count
        refute_dogstats_count "security_overview_analytics.dependabot_alert_revisions.severities_updated"
      end

      test "does nothing if it's an unsupported metadata change" do
        FeatureFlagHelper.stubs(:instrument_vulnerability_update_events?).returns(true)

        repo_metadata = create(:soa_repository, repository: @repo)

        date = create(:security_overview_analytics_date, date_value: Time.now.utc)
        create(:soa_dependabot_alert_revision, date_id: 20240101, next_revision_date_id: 20240102, repository_metadata: repo_metadata, alert_number: 101, alert_severity: @vulnerability.severity)
        create(:soa_dependabot_alert_revision, date_id: 20240102, next_revision_date_id: 99991231, repository_metadata: repo_metadata, alert_number: 101, alert_severity: @vulnerability.severity)
        # This one won't get updated because it's a different alert number
        create(:soa_dependabot_alert_revision, date:, repository_metadata: repo_metadata, alert_number: 102, alert_severity: @vulnerability.severity)

        assert_equal 3, DependabotAlertRevision.where(alert_severity: @vulnerability.severity).count

        assert_query_count_per_table({
          soa_dependabot_alert_revisions: 0,
        }) do
          perform_hydro_message_job(
            event_message(action: "vulnerability_metadata_change", repository_id: @repo.id, repository_vulnerability_alert_number: 101, severity: "low"),
            schema: @schema,
            queue: @queue,
          )
        end

        assert_equal 3, DependabotAlertRevision.where(alert_severity: @vulnerability.severity).count
        assert_equal 0, DependabotAlertRevision.where(alert_severity: "low").count
        refute_dogstats_count "security_overview_analytics.dependabot_alert_revisions.severities_updated"
      end

      test "does nothing if feature flag is off" do
        FeatureFlagHelper.stubs(:instrument_vulnerability_update_events?).returns(false)

        repo_metadata = create(:soa_repository, repository: @repo)

        date = create(:security_overview_analytics_date, date_value: Time.now.utc)
        create(:soa_dependabot_alert_revision, date_id: 20240101, next_revision_date_id: 20240102, repository_metadata: repo_metadata, alert_number: 101, alert_severity: @vulnerability.severity)
        create(:soa_dependabot_alert_revision, date_id: 20240102, next_revision_date_id: 99991231, repository_metadata: repo_metadata, alert_number: 101, alert_severity: @vulnerability.severity)
        # This one won't get updated because it's a different alert number
        create(:soa_dependabot_alert_revision, date:, repository_metadata: repo_metadata, alert_number: 102, alert_severity: @vulnerability.severity)

        assert_equal 3, DependabotAlertRevision.where(alert_severity: @vulnerability.severity).count

        assert_query_count_per_table({
          soa_dependabot_alert_revisions: 0,
        }) do
          perform_hydro_message_job(
            event_message(action: "severity_change", repository_id: @repo.id, repository_vulnerability_alert_number: 101, severity: "low"),
            schema: @schema,
            queue: @queue,
          )
        end

        assert_equal 3, DependabotAlertRevision.where(alert_severity: @vulnerability.severity).count
        assert_equal 0, DependabotAlertRevision.where(alert_severity: "low").count
        refute_dogstats_count "security_overview_analytics.dependabot_alert_revisions.severities_updated"
      end
    end

    context "when alerts being withdrawn" do
      test "delete alert revisions on withdraw event" do
        create(:soa_dependabot_alert_revision, repository: @repo, alert_number: @alert.number)

        assert_equal 1, DependabotAlertRevision.count
        UpdateFeatureStatusSummaryJob.expects(:enqueue).once

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
