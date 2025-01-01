# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class RevisionUpserterTest < GitHub::TestCase
    include DogstatsTestHelpers

    fixtures do
      @org = create(:business_plus_organization)
      @repo = create(:repository, owner: @org)
    end

    setup do
      SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:report_duplicate_revisions?).returns(false)
    end

    context "#upsert" do
      test "retries if it fails to insert a record that already exists" do
        repository_id = @repo.id
        alert_number = 1
        date_id = 20231011
        next_revision_date_id = 99991231

        revision = create(:soa_dependabot_alert_revision, date_id:, next_revision_date_id:, repository_id:, alert_number:)
        payload = DependabotAlertRevision::UpdatePayload.new(
          alert_created_at: revision.alert_created_at,
          alert_resolved: revision.alert_resolved,
          alert_updated_at: revision.alert_updated_at + 1.day,
          ghsa_id: revision.ghsa_id,
          dependency_scope: revision.dependency_scope.to_sym,
          ecosystem: revision.ecosystem,
          package_name: revision.package_name,
        )

        upserter = SecurityOverviewAnalytics::RevisionUpserter.new(DependabotAlertRevision)

        # Prevent the existing record from being found
        DependabotAlertRevision.stubs(:where).returns(DependabotAlertRevision.none)

        raised = states("raised").starts_as("no")
        DependabotAlertRevision \
          .expects(:create!)
          .once
          .with { DependabotAlertRevision.unstub(:where) } # Allow the existing record to be found on the second attempt
          .then(raised.is("yes"))
          .raises(ActiveRecord::RecordNotUnique)
        DependabotAlertRevision \
          .any_instance
          .expects(:update!)
          .once
          .when(raised.is("yes"))

        upserter.upsert(payload, repository_id:, alert_number:, date_id:)
      end

      test "it sets alert_reopened_at when an alert is reopened" do
        repository_id = @repo.id
        alert_number = 1
        date_id = 20231011
        next_revision_date_id = 99991231

        revision = create(:soa_dependabot_alert_revision, date_id:, next_revision_date_id:, repository_id:, alert_number:, alert_resolved: true)

        payload = DependabotAlertRevision::UpdatePayload.new(
          alert_created_at: revision.alert_created_at,
          alert_resolved: false,
          alert_updated_at: revision.alert_updated_at + 1.day,
          ghsa_id: revision.ghsa_id,
          dependency_scope: revision.dependency_scope.to_sym,
          ecosystem: revision.ecosystem,
          package_name: revision.package_name,
        )

        upserter = SecurityOverviewAnalytics::RevisionUpserter.new(DependabotAlertRevision)
        upserter.upsert(payload, repository_id:, alert_number:, date_id: date_id + 1)

        refute_nil T.must(DependabotAlertRevision.where(alert_number:, date_id: date_id + 1).first).alert_reopened_at
        assert_equal revision.alert_updated_at + 1.day, T.must(DependabotAlertRevision.where(alert_number:, date_id: date_id + 1).first).alert_reopened_at
      end

      test "it queries revisions by alert_id AND alert_number == alert_id when alert_id is present" do
        repository_id = @repo.id
        alert_id = 1
        alert_number = 3
        date_id = 20231011
        next_revision_date_id = 99991231

        revision = create(:soa_code_scanning_alert_revision, date_id:, next_revision_date_id:, repository_id:, alert_number: alert_id, alert_id:, alert_resolved: true)
        revision2 = create(:soa_code_scanning_alert_revision, date_id:, next_revision_date_id:, repository_id:, alert_number: alert_number + 1, alert_id: alert_id, alert_resolved: true)

        payload = CodeScanningAlertRevision::UpdatePayload.new(
          alert_created_at: revision.alert_created_at,
          alert_resolved: false,
          alert_updated_at: revision.alert_updated_at + 1.day,
          tool: "CodeQL",
          rule_sarif_identifier: "rule_sarif_identifier",
          alert_id:,
        )

        upserter = SecurityOverviewAnalytics::RevisionUpserter.new(CodeScanningAlertRevision)
        upserter.upsert(payload, repository_id:, alert_number:, date_id: date_id + 1, alert_id:)

        refute_nil T.must(CodeScanningAlertRevision.where(alert_number:, date_id: date_id + 1).first).alert_reopened_at
        assert_equal revision.alert_updated_at + 1.day, T.must(CodeScanningAlertRevision.where(alert_number:, date_id: date_id + 1).first).alert_reopened_at
        assert_nil CodeScanningAlertRevision.where(alert_number: alert_number + 1, date_id: date_id + 1).first
      end

      test "it updates the revision in place and sets alert_reopened_at when an alert is closed and reopened on the same day" do
        repository_id = @repo.id
        alert_number = 1
        date_id = 20231011
        next_revision_date_id = 99991231

        revision = create(:soa_dependabot_alert_revision, date_id:, next_revision_date_id:, repository_id:, alert_number:, alert_resolved: true)

        payload = DependabotAlertRevision::UpdatePayload.new(
          alert_created_at: revision.alert_created_at,
          alert_resolved: false,
          alert_updated_at: revision.alert_updated_at + 1.minute,
          ghsa_id: revision.ghsa_id,
          dependency_scope: revision.dependency_scope.to_sym,
          ecosystem: revision.ecosystem,
          package_name: revision.package_name,
        )

        upserter = SecurityOverviewAnalytics::RevisionUpserter.new(DependabotAlertRevision)
        upserter.upsert(payload, repository_id:, alert_number:, date_id:)

        refute_nil T.must(DependabotAlertRevision.where(id: revision.id).first).alert_reopened_at
        assert_equal revision.alert_updated_at + 1.minute, T.must(DependabotAlertRevision.where(id: revision.id).first).alert_reopened_at
      end

      test "it carries alert_reopened_at over to the next revision" do
        repository_id = @repo.id
        alert_number = 1
        date_id = 20231011
        next_revision_date_id = 99991231

        revision = create(
          :soa_dependabot_alert_revision,
          date_id:,
          next_revision_date_id:,
          repository_id:,
          alert_number:,
          alert_resolved: false,
          alert_reopened_at: Time.now
        )

        payload = DependabotAlertRevision::UpdatePayload.new(
          alert_created_at: revision.alert_created_at,
          alert_resolved: true,
          alert_updated_at: revision.alert_updated_at + 1.day,
          ghsa_id: revision.ghsa_id,
          dependency_scope: revision.dependency_scope.to_sym,
          ecosystem: revision.ecosystem,
          package_name: revision.package_name,
        )

        upserter = SecurityOverviewAnalytics::RevisionUpserter.new(DependabotAlertRevision)
        upserter.upsert(payload, repository_id:, alert_number:, date_id: date_id + 1)

        refute_nil T.must(DependabotAlertRevision.where(alert_number:, date_id: date_id + 1).first).alert_reopened_at
        assert_equal revision.alert_reopened_at, T.must(DependabotAlertRevision.where(alert_number:, date_id: date_id + 1).first).alert_reopened_at
      end

      test "it updates the revision in place and keeps alert_reopened_at field when a revision is reopened and modified on the same day" do
        repository_id = @repo.id
        alert_number = 1
        date_id = 20231011
        next_revision_date_id = 99991231

        revision = create(
          :soa_dependabot_alert_revision,
          date_id:,
          next_revision_date_id:,
          repository_id:,
          alert_number:,
          alert_resolved: false,
          alert_reopened_at: Time.now
        )

        payload = DependabotAlertRevision::UpdatePayload.new(
          alert_created_at: revision.alert_created_at,
          alert_resolved: true,
          alert_updated_at: revision.alert_updated_at + 1.minute,
          ghsa_id: revision.ghsa_id,
          dependency_scope: revision.dependency_scope.to_sym,
          ecosystem: revision.ecosystem,
          package_name: revision.package_name,
        )

        upserter = SecurityOverviewAnalytics::RevisionUpserter.new(DependabotAlertRevision)
        upserter.upsert(payload, repository_id:, alert_number:, date_id:)

        refute_nil T.must(DependabotAlertRevision.where(alert_number:, date_id:).first).alert_reopened_at
        assert_equal revision.alert_reopened_at, T.must(DependabotAlertRevision.where(alert_number:, date_id:).first).alert_reopened_at
      end

      test "it keeps alert_reopened_at field as null when a revision is modified but has not been reopened" do
        repository_id = @repo.id
        alert_number = 1
        date_id = 20231011
        next_revision_date_id = 99991231

        revision = create(
          :soa_dependabot_alert_revision,
          date_id:,
          next_revision_date_id:,
          repository_id:,
          alert_number:,
          alert_resolved: false,
        )

        payload = DependabotAlertRevision::UpdatePayload.new(
          alert_created_at: revision.alert_created_at,
          alert_resolved: true,
          alert_updated_at: revision.alert_updated_at + 1.day,
          ghsa_id: revision.ghsa_id,
          dependency_scope: revision.dependency_scope.to_sym,
          ecosystem: revision.ecosystem,
          package_name: revision.package_name,
        )

        upserter = SecurityOverviewAnalytics::RevisionUpserter.new(DependabotAlertRevision)
        upserter.upsert(payload, repository_id:, alert_number:, date_id: date_id + 1)

        assert_nil T.must(DependabotAlertRevision.where(alert_number:, date_id: date_id + 1).first).alert_reopened_at
      end

      test "it updates the revision in place and keeps alert_reopened_at field as null when a revision that has not been reopened is modified on the same day " do
        repository_id = @repo.id
        alert_number = 1
        date_id = 20231011
        next_revision_date_id = 99991231

        revision = create(
          :soa_dependabot_alert_revision,
          date_id:,
          next_revision_date_id:,
          repository_id:,
          alert_number:,
          alert_resolved: false,
        )

        payload = DependabotAlertRevision::UpdatePayload.new(
          alert_created_at: revision.alert_created_at,
          alert_resolved: true,
          alert_updated_at: revision.alert_updated_at + 1.minute,
          ghsa_id: revision.ghsa_id,
          dependency_scope: revision.dependency_scope.to_sym,
          ecosystem: revision.ecosystem,
          package_name: revision.package_name,
        )

        upserter = SecurityOverviewAnalytics::RevisionUpserter.new(DependabotAlertRevision)
        upserter.upsert(payload, repository_id:, alert_number:, date_id:)

        assert_nil T.must(DependabotAlertRevision.where(alert_number:, date_id:).first).alert_reopened_at
      end

      test "skips the revision if a newer revision exists outside of retention limit" do
        now = Time.now
        date_now = create(:soa_date, date_value: now)

        three_years_ago = 3.years.ago
        date_three_years_ago = create(:security_overview_analytics_date, date_value: three_years_ago)
        older_than_date_three_years_ago = create(:security_overview_analytics_date, date_value: three_years_ago - 1.day)

        metadata = create(:soa_repository, repository: @repo)

        create(:soa_dependabot_alert_revision, repository_metadata: metadata, date: date_now)
        next_revision = create(
          :soa_dependabot_alert_revision,
          repository_metadata: metadata,
          date: date_three_years_ago,
          next_revision_date_id: Date.id_from_time(now)
        )

        payload = DependabotAlertRevision::UpdatePayload.new(
          alert_created_at: next_revision.alert_created_at,
          alert_resolved: next_revision.alert_resolved,
          alert_updated_at: next_revision.alert_updated_at + 1.day,
          ghsa_id: next_revision.ghsa_id,
          dependency_scope: next_revision.dependency_scope.to_sym,
          ecosystem: next_revision.ecosystem,
          package_name: next_revision.package_name,
        )

        upserter = RevisionUpserter.new(DependabotAlertRevision)
        upserter.upsert(payload, repository_id: @repo.id, alert_number: next_revision.alert_number, date_id: older_than_date_three_years_ago.id)
        assert_nil DependabotAlertRevision.find_by(alert_number: next_revision.alert_number, date_id: older_than_date_three_years_ago.id)

        assert_dogstats_increment 1, "security_overview_analytics.revision.upsert.succeeded", tags: ["feature_type:dependabot_alerts", "upsert_scenario:upsert_skipped_for_retention_limit", "force_rewrite:false"]
      end

      test "reports broken revision chain properly if found any" do
        alert_number = 1

        alert_created_at = Time.parse("2023-11-25T00:00:00Z")
        alert_updated_at = Time.parse("2024-01-01T00:00:00Z")
        last_revision_date = Time.parse("2023-11-26T00:00:00Z")
        [
          create(:security_overview_analytics_date, date_value: Time.parse("2023-11-27")),
          create(:security_overview_analytics_date, date_value: Time.parse("2023-11-26")),
          create(:security_overview_analytics_date, date_value: Time.parse("2023-11-25")),
        ].reduce("20231128") do |next_date_id, date|
          create(
            :soa_dependabot_alert_revision,
            repository_id: @repo.id,
            alert_number: alert_number,
            date: date,
            next_revision_date_id: date.date_value == last_revision_date.to_date ? ::SecurityOverviewAnalytics::Date::FUTURE_DATE_ID : next_date_id,
            alert_created_at: alert_created_at,
            alert_updated_at: date.date_value >= last_revision_date.to_date ? last_revision_date.to_date : date.date_value,
            created_at: date.date_value,
            updated_at: date.date_value == last_revision_date.to_date ? alert_updated_at.to_date : date.date_value,
          )
          next date.id
        end

        payload = DependabotAlertRevision::UpdatePayload.new(
          alert_created_at: alert_created_at,
          alert_resolved: false,
          alert_updated_at: alert_updated_at,
          ghsa_id: "GHSA-1234-5678-90AB",
          dependency_scope: :RUNTIME,
          ecosystem: "npm",
          package_name: "react",
        )
        upserter = RevisionUpserter.new(DependabotAlertRevision)

        assert_raises ActiveRecord::RecordNotUnique do
          upserter.upsert(payload, repository_id: @repo.id, alert_number: alert_number, date_id: Date.id_from_time(alert_updated_at))
        end

        assert_dogstats_increment 1, "security_overview_analytics.revision_upserter.broken_revision_chain.detected", tags: ["feature_type:dependabot_alerts"]
      end

      test "reports duplicate revisions properly if found any and flag is on" do
        FeatureFlagHelper.stubs(:report_duplicate_revisions?).returns(true)

        repository_id = @repo.id
        alert_number = 1
        date_id = 20231011
        new_date_id = 20231025
        next_revision_date_id = 99991231

        revision = create(
          :soa_dependabot_alert_revision,
          date_id:,
          next_revision_date_id:,
          repository_id:,
          alert_number:,
          alert_resolved: false,
        )

        required_fields = DependabotAlertRevision::UpdatePayload.props.select { |_, v| v[:immutable] }.keys
        revision_hash = revision.attributes.symbolize_keys.select { |k| required_fields.include?(k) }
        revision_hash[:alert_severity] = revision_hash[:alert_severity].to_sym
        revision_hash[:dependency_scope] = revision_hash[:dependency_scope].to_sym

        payload = DependabotAlertRevision::UpdatePayload.new(revision_hash)
        upserter = RevisionUpserter.new(DependabotAlertRevision)

        assert_equal 1, DependabotAlertRevision.count
        upserter.upsert(payload, repository_id:, alert_number:, date_id: new_date_id)

        assert_equal 2, DependabotAlertRevision.count
        assert_dogstats_increment 1, "security_overview_analytics.revision_upserter.duplicate_revisions.detected", tags: ["feature_type:dependabot_alerts"]
      end

      test "reconnects broken chain if found and flag is on" do
        repository_id = @repo.id
        alert_number = 131

        revision1 = create(
          :soa_code_scanning_alert_revision,
          date_id: 20240304,
          next_revision_date_id: 20240429,
          repository_id:,
          alert_number:,
          alert_resolved: false,
        )
        # No revision for 20240429
        revision2 = create(
          :soa_code_scanning_alert_revision,
          date_id: 20240529,
          next_revision_date_id: 99991231,
          repository_id:,
          alert_number:,
          alert_resolved: false,
        )

        payload = CodeScanningAlertRevision::UpdatePayload.new(
          alert_created_at: revision1.alert_created_at + 1.day,
          alert_resolved: false,
          alert_updated_at: revision1.alert_updated_at + 1.day,
          tool: "CodeQL",
          rule_sarif_identifier: "rule_sarif_identifier",
        )

        upserter = RevisionUpserter.new(CodeScanningAlertRevision)
        assert_nothing_raised do
          upserter.upsert(payload, repository_id:, alert_number:, date_id: 20240429)
        end

        assert_equal CodeScanningAlertRevision.where(repository_id:, alert_number:, date_id: 20240429).first.next_revision_date_id, 20240529
      end
    end
  end
end
