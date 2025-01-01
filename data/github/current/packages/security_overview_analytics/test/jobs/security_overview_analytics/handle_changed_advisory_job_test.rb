# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "hydro/schemas/github/security_alerts/v1/repository_vulnerability_alert_lifecycle_event_pb"

module SecurityOverviewAnalytics
  class HandleChangedAdvisoryJobTest < GitHub::TestCase
    include JobTestHelper

    fixtures do
      @repo = create(:repository)
      @vulnerability = create(:vulnerability, severity: "high")
      @vulnerable_version_range = create(:vulnerable_version_range, affects: "react", fixed_in: "2", ecosystem: "npm", vulnerability: @vulnerability)
    end

    setup do
      SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:handle_changed_advisory_job_run_two_part_query?).returns(true)
    end

    context "#before_perform" do
      test "raises an error if source_event is not provided" do
        assert_raises_with_message(ArgumentError, "Must provide source_event.") do
          HandleChangedAdvisoryJob.perform_now(vulnerability_id: @vulnerability.id)
        end
      end

      test "raises an error if neither vulnerability_id nor vulnerable_version_range_id are provided" do
        assert_raises_with_message(ArgumentError, "Either vulnerability_id or vulnerable_version_range_id must be provided.") do
          HandleChangedAdvisoryJob.perform_now(source_event: HandleChangedAdvisoryJob::WITHDRAW_SOURCE_EVENT)
        end
      end

      test "raises an error if both vulnerability_id and vulnerable_version_range_id are provided" do
        assert_raises_with_message(ArgumentError, "Only vulnerability_id or vulnerable_version_range_id can be provided.") do
          HandleChangedAdvisoryJob.perform_now(
            vulnerability_id: @vulnerability.id,
            vulnerable_version_range_id: @vulnerable_version_range.id,
            source_event: HandleChangedAdvisoryJob::WITHDRAW_SOURCE_EVENT,
          )
        end
      end

      test "raises error if vulnerability_id is not provided for update source_event" do
        assert_raises_with_message(ArgumentError, "Must provide vulnerability_id to react to advisory update event.") do
          HandleChangedAdvisoryJob.perform_now(vulnerable_version_range_id: @vulnerable_version_range.id, source_event: HandleChangedAdvisoryJob::UPDATE_SOURCE_EVENT)
        end
      end

      test "no error if all required arguments are provided" do
        HandleChangedAdvisoryJob.perform_now(vulnerability_id: @vulnerability.id, source_event: HandleChangedAdvisoryJob::WITHDRAW_SOURCE_EVENT)
        HandleChangedAdvisoryJob.perform_now(vulnerable_version_range_id: @vulnerable_version_range.id, source_event: HandleChangedAdvisoryJob::WITHDRAW_SOURCE_EVENT)
      end
    end

    context "#perform" do
      context "source_event is '#{HandleChangedAdvisoryJob::WITHDRAW_SOURCE_EVENT}'" do
        test "deletes matching revision from service" do
          vuln = create(:vulnerability, severity: "high")
          alert = create(:repository_vulnerability_alert, repository: @repo, vulnerability: vuln)
          revision = create(:soa_dependabot_alert_revision, repository_id: alert.repository_id, alert_number: alert.number)

          assert_equal 1, DependabotAlertRevision.count

          assert_query_count(4, ignore_feature_flags: true) do # one for the alerts list, one for revision existence, one for deletion
            HandleChangedAdvisoryJob.perform_now(vulnerability_id: alert.vulnerability_id, source_event: HandleChangedAdvisoryJob::WITHDRAW_SOURCE_EVENT)
          end

          refute DependabotAlertRevision.any?
        end

        test "deletes all matching revisions for an alert from service" do
          vuln = create(:vulnerability, severity: "high")
          alert = create(:repository_vulnerability_alert, repository: @repo, vulnerability: vuln)

          revision1 = create(
            :soa_dependabot_alert_revision,
            date_id: 20231011,
            next_revision_date_id: 20231012,
            repository_id: alert.repository_id,
            alert_number: alert.number,
          )
          revision2 = create(
            :soa_dependabot_alert_revision,
            date_id: revision1.next_revision_date_id,
            repository_id: revision1.repository_id,
            alert_number: revision1.alert_number,
          )

          assert_equal 2, DependabotAlertRevision.count

          assert_query_count(4, ignore_feature_flags: true) do
            HandleChangedAdvisoryJob.perform_now(vulnerability_id: alert.vulnerability_id, source_event: HandleChangedAdvisoryJob::WITHDRAW_SOURCE_EVENT)
          end

          refute DependabotAlertRevision.any?
        end

        test "deletes only matched revisions for multiple alerts by vulnerability_id" do
          vuln = create(:vulnerability, severity: "high")

          alert1 = create(:repository_vulnerability_alert, repository: @repo)
          alert2 = create(:repository_vulnerability_alert, repository: @repo, vulnerability: vuln)
          alert3 = create(:repository_vulnerability_alert, repository: @repo, vulnerable_version_range_id: alert1.vulnerable_version_range_id)

          repo2 = create(:repository)
          alert4 = create(:repository_vulnerability_alert, repository: repo2, vulnerability_id: alert2.vulnerability_id)
          alert5 = create(:repository_vulnerability_alert, repository: repo2)
          alert6 = create(:repository_vulnerability_alert, repository: repo2, vulnerability_id: alert2.vulnerability_id)

          create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert1.repository_id, alert_number: alert1.number)
          create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert2.repository_id, alert_number: alert2.number)
          create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert3.repository_id, alert_number: alert3.number)
          create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert4.repository_id, alert_number: alert4.number)
          create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert5.repository_id, alert_number: alert5.number)
          create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert6.repository_id, alert_number: alert6.number)

          assert_equal 6, DependabotAlertRevision.count

          assert_query_count(6, ignore_feature_flags: true) do
            HandleChangedAdvisoryJob.perform_now(vulnerability_id: alert2.vulnerability_id, source_event: HandleChangedAdvisoryJob::WITHDRAW_SOURCE_EVENT)
          end

          assert_equal 3, DependabotAlertRevision.count
          [alert1, alert3, alert5].each do |alert|
            assert DependabotAlertRevision.where(repository_id: alert.repository_id, alert_number: alert.number).exists?
          end
        end

        test "deletes only matched revisions for multiple alerts by vulnerable_version_range_id" do
          vuln = create(:vulnerability, severity: "high")
          vvr1 = create(:vulnerable_version_range, affects: "react", fixed_in: "2", ecosystem: "npm", vulnerability: vuln)
          vvr2 = create(:vulnerable_version_range, affects: "npm-package", fixed_in: "1", ecosystem: "npm", vulnerability: vuln)

          alert1 = create(:repository_vulnerability_alert, repository: @repo, vulnerability: vuln, vulnerable_version_range: vvr1)
          alert2 = create(:repository_vulnerability_alert, repository: @repo, vulnerability: vuln, vulnerable_version_range: vvr2)
          alert3 = create(:repository_vulnerability_alert, repository: @repo)

          repo2 = create(:repository)
          alert4 = create(:repository_vulnerability_alert, repository: repo2, vulnerability: vuln, vulnerable_version_range: vvr1)
          alert5 = create(:repository_vulnerability_alert, repository: repo2)
          alert6 = create(:repository_vulnerability_alert, repository: repo2, vulnerability: vuln, vulnerable_version_range: vvr2)

          create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert1.repository_id, alert_number: alert1.number)
          create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert2.repository_id, alert_number: alert2.number)
          create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert3.repository_id, alert_number: alert3.number)
          create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert4.repository_id, alert_number: alert4.number)
          create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert5.repository_id, alert_number: alert5.number)
          create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert6.repository_id, alert_number: alert6.number)

          assert_equal 6, DependabotAlertRevision.count

          assert_query_count(6, ignore_feature_flags: true) do
            HandleChangedAdvisoryJob.perform_now(vulnerable_version_range_id: alert2.vulnerable_version_range_id, source_event: HandleChangedAdvisoryJob::WITHDRAW_SOURCE_EVENT)
          end

          assert_equal 4, DependabotAlertRevision.count
          [alert1, alert3, alert4, alert5].each do |alert|
            assert DependabotAlertRevision.where(repository_id: alert.repository_id, alert_number: alert.number).exists?
          end
        end

        test "queues another job if there are more alerts to withdraw than BATCH_SIZE" do
          vuln = create(:vulnerability, severity: "high")

          alert1 = create(:repository_vulnerability_alert, repository: @repo, vulnerability: vuln)
          alert2 = create(:repository_vulnerability_alert, repository: @repo, vulnerability_id: alert1.vulnerability_id)
          alert3 = create(:repository_vulnerability_alert, repository: @repo, vulnerability_id: alert1.vulnerability_id)

          repo2 = create(:repository)
          alert4 = create(:repository_vulnerability_alert, repository: repo2, vulnerability_id: alert1.vulnerability_id)
          alert5 = create(:repository_vulnerability_alert, repository: repo2, vulnerability_id: alert1.vulnerability_id)
          alert6 = create(:repository_vulnerability_alert, repository: repo2, vulnerability_id: alert1.vulnerability_id)

          rev1 = create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert1.repository_id, alert_number: alert1.number)
          rev2 = create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert2.repository_id, alert_number: alert2.number)
          rev3 = create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert3.repository_id, alert_number: alert3.number)
          rev4 = create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert4.repository_id, alert_number: alert4.number)
          rev5 = create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert5.repository_id, alert_number: alert5.number)
          rev6 = create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert6.repository_id, alert_number: alert6.number)

          assert_equal 6, DependabotAlertRevision.count

          HandleChangedAdvisoryJob.stub_const(:BATCH_SIZE, 4) do
            assert_enqueued_with(job: HandleChangedAdvisoryJob, args: ->(args) {
              assert_equal alert1.vulnerability_id, args.first[:vulnerability_id]
              assert_equal args.first[:source_event], HandleChangedAdvisoryJob::WITHDRAW_SOURCE_EVENT, "source_event"
              assert_equal args.first[:offset_item_id], alert4.id, "offset_item_id"
              assert_equal args.first[:progress], 4, "progress"
            }) do
              assert_query_count(6, ignore_feature_flags: true) do
                HandleChangedAdvisoryJob.perform_now(vulnerability_id: alert1.vulnerability_id, source_event: HandleChangedAdvisoryJob::WITHDRAW_SOURCE_EVENT)
              end
            end
          end

          assert_equal 2, DependabotAlertRevision.count
          [alert5, alert6].each do |alert|
            assert DependabotAlertRevision.where(repository_id: alert.repository_id, alert_number: alert.number).exists?
          end
        end
      end

      context "source_event is '#{HandleChangedAdvisoryJob::UPDATE_SOURCE_EVENT}'" do
        test "updates matching revision" do
          vuln = create(:vulnerability, severity: :critical)
          alert = create(:repository_vulnerability_alert, vulnerability_id: vuln.id, repository: @repo)
          revision = create(:soa_dependabot_alert_revision, alert_severity: :HIGH, repository_id: alert.repository_id, alert_number: alert.number)

          assert_equal "HIGH", T.must(DependabotAlertRevision.first).alert_severity

          assert_query_count(5, ignore_feature_flags: true) do
            HandleChangedAdvisoryJob.perform_now(vulnerability_id: alert.vulnerability_id, source_event: HandleChangedAdvisoryJob::UPDATE_SOURCE_EVENT)
          end

          assert_equal "CRITICAL", T.must(DependabotAlertRevision.first).alert_severity
        end

        test "updates all matching revision for an alert" do
          vuln = create(:vulnerability, severity: :moderate)
          alert = create(:repository_vulnerability_alert, vulnerability_id: vuln.id, repository: @repo)
          revision1 = create(
            :soa_dependabot_alert_revision,
            date_id: 20231011,
            next_revision_date_id: 20231012,
            alert_number: alert.number,
            repository_id: alert.repository_id,
          )
          revision2 = create(
            :soa_dependabot_alert_revision,
            date_id: revision1.next_revision_date_id,
            repository_id: revision1.repository_id,
            alert_number: revision1.alert_number,
          )

          DependabotAlertRevision.all.each do |revision|
            assert_equal "LOW", revision.alert_severity
          end

          assert_query_count(5, ignore_feature_flags: true) do
            HandleChangedAdvisoryJob.perform_now(vulnerability_id: alert.vulnerability_id, source_event: HandleChangedAdvisoryJob::UPDATE_SOURCE_EVENT)
          end

          DependabotAlertRevision.all.each do |revision|
            assert_equal "MODERATE", revision.alert_severity
          end
        end

        test "updates only matched revisions for multiple alerts" do
          vuln = create(:vulnerability, severity: :critical)

          alert1 = create(:repository_vulnerability_alert, repository: @repo)
          alert2 = create(:repository_vulnerability_alert, repository: @repo, vulnerability_id: vuln.id)
          alert3 = create(:repository_vulnerability_alert, repository: @repo)

          repo2 = create(:repository)
          alert4 = create(:repository_vulnerability_alert, repository: repo2, vulnerability_id: alert2.vulnerability_id)
          alert5 = create(:repository_vulnerability_alert, repository: repo2)
          alert6 = create(:repository_vulnerability_alert, repository: repo2, vulnerability_id: alert2.vulnerability_id)

          create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert1.repository_id, alert_number: alert1.number)
          create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert2.repository_id, alert_number: alert2.number)
          create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert3.repository_id, alert_number: alert3.number)
          create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert4.repository_id, alert_number: alert4.number)
          create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert5.repository_id, alert_number: alert5.number)
          create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert6.repository_id, alert_number: alert6.number)

          DependabotAlertRevision.all.each do |revision|
            assert_equal "LOW", revision.alert_severity
          end

          assert_query_count(7, ignore_feature_flags: true) do
            HandleChangedAdvisoryJob.perform_now(vulnerability_id: alert2.vulnerability_id, source_event: HandleChangedAdvisoryJob::UPDATE_SOURCE_EVENT)
          end

          [alert2, alert4, alert6].each do |alert|
            assert_equal "CRITICAL", DependabotAlertRevision.find_by(repository_id: alert.repository_id, alert_number: alert.number)&.alert_severity
          end

          [alert1, alert3, alert5].each do |alert|
            assert_equal "LOW", DependabotAlertRevision.find_by(repository_id: alert.repository_id, alert_number: alert.number)&.alert_severity
          end
        end

        test "queues another job if there are more alerts to update than BATCH_SIZE" do
          vuln = create(:vulnerability, severity: :critical)

          alert1 = create(:repository_vulnerability_alert, repository: @repo, vulnerability_id: vuln.id)
          alert2 = create(:repository_vulnerability_alert, repository: @repo, vulnerability_id: alert1.vulnerability_id)
          alert3 = create(:repository_vulnerability_alert, repository: @repo, vulnerability_id: alert1.vulnerability_id)

          repo2 = create(:repository)
          alert4 = create(:repository_vulnerability_alert, repository: repo2, vulnerability_id: alert1.vulnerability_id)
          alert5 = create(:repository_vulnerability_alert, repository: repo2, vulnerability_id: alert1.vulnerability_id)
          alert6 = create(:repository_vulnerability_alert, repository: repo2, vulnerability_id: alert1.vulnerability_id)

          rev1 = create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert1.repository_id, alert_number: alert1.number)
          rev2 = create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert2.repository_id, alert_number: alert2.number)
          rev3 = create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert3.repository_id, alert_number: alert3.number)
          rev4 = create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert4.repository_id, alert_number: alert4.number)
          rev5 = create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert5.repository_id, alert_number: alert5.number)
          rev6 = create(:soa_dependabot_alert_revision, date_id: 20231011, next_revision_date_id: 99991231, repository_id: alert6.repository_id, alert_number: alert6.number)

          DependabotAlertRevision.all.each do |revision|
            assert_equal "LOW", revision.alert_severity
          end

          HandleChangedAdvisoryJob.stub_const(:BATCH_SIZE, 4) do
            assert_enqueued_with(job: HandleChangedAdvisoryJob, args: ->(args) {
              assert_equal alert1.vulnerability_id, args.first[:vulnerability_id]
              assert_equal args.first[:source_event], HandleChangedAdvisoryJob::UPDATE_SOURCE_EVENT, "source_event"
              assert_equal args.first[:offset_item_id], alert4.id, "offset_item_id"
              assert_equal args.first[:progress], 4, "progress"
            }) do
              assert_query_count(7, ignore_feature_flags: true) do
                HandleChangedAdvisoryJob.perform_now(vulnerability_id: alert2.vulnerability_id, source_event: HandleChangedAdvisoryJob::UPDATE_SOURCE_EVENT)
              end
            end
          end

          [alert1, alert2, alert3, alert4].each do |alert|
            assert_equal "CRITICAL", DependabotAlertRevision.find_by(repository_id: alert.repository_id, alert_number: alert.number)&.alert_severity
          end

          [alert5, alert6].each do |alert|
            assert_equal "LOW", DependabotAlertRevision.find_by(repository_id: alert.repository_id, alert_number: alert.number)&.alert_severity
          end
        end
      end
    end
  end
end
