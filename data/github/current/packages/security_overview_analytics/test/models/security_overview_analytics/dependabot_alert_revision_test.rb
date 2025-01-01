# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class DependabotAlertRevisionTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers
    include SecurityCenter::TestHelpers

    Event = Hydro::Schemas::Github::SecurityAlerts::V1::RepositoryVulnerabilityAlertLifecycleEvent
    DependabotResolutions = Event::LastStateChangeReason

    fixtures do
      @org = create(:business_plus_organization)
      @repo = create(:repository, owner: @org)
    end

    context ".to_closure_reasons" do
      test "returns the closure reasons mapped to fixed_or_revoked" do
        reasons = DependabotAlertRevision.to_closure_reasons([:fixed_or_revoked])
        assert_equal reasons, DependabotAlertRevision::RESOLUTIONS_MAPPING[:fixed_or_revoked]
      end

      test "returns the closure reasons mapped to auto_dismissed" do
        reasons = DependabotAlertRevision.to_closure_reasons([:auto_dismissed])
        assert_equal reasons, DependabotAlertRevision::RESOLUTIONS_MAPPING[:auto_dismissed]
      end

      test "returns the closure reasons mapped to false_positive" do
        reasons = DependabotAlertRevision.to_closure_reasons([:false_positive])
        assert_equal reasons, DependabotAlertRevision::RESOLUTIONS_MAPPING[:false_positive]
      end

      test "returns the closure reasons mapped to risk_accepted" do
        reasons = DependabotAlertRevision.to_closure_reasons([:risk_accepted])
        assert_equal reasons, DependabotAlertRevision::RESOLUTIONS_MAPPING[:risk_accepted]
      end

      test "returns the closure reasons mapped to multiple filters" do
        reasons = DependabotAlertRevision.to_closure_reasons([:fixed_or_revoked, :risk_accepted])
        mapped_reasons = [DependabotAlertRevision::RESOLUTIONS_MAPPING[:fixed_or_revoked], DependabotAlertRevision::RESOLUTIONS_MAPPING[:risk_accepted]].flatten
        assert_equal reasons, mapped_reasons
      end
    end

    context ".to_valid_severities" do
      test "returns 'medium' as 'moderate' severity" do
        severities = DependabotAlertRevision.to_valid_severities(%w[low medium high])
        assert_equal severities, %w[low moderate high]
      end
    end

    context "field_with_deviations" do
      test "returns the fields with deviations" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        alert = create(:repository_vulnerability_alert,
            vulnerable_manifest_path: "package.json",
            affects: "react",
            repository: repo,
          )
        revision = create(:soa_dependabot_alert_revision, repository_id: repo.id, alert_number: alert.number)
        alert.fix(reason: :DEPENDENCY_CHANGED, push_id: 123)

        assert_equal [:alert_resolved, :alert_severity, :ghsa_id, :ecosystem, :alert_resolution], revision.fields_with_deviation(alert:)
      end

      test "properly converts and compares resolution reasons" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        alert = create(:repository_vulnerability_alert,
            vulnerable_manifest_path: "package.json",
            affects: "react",
            repository: repo,
            last_state_change_at: nil,
          )
        revision = create(:soa_dependabot_alert_revision,
          repository_id: repo.id,
          alert_number: alert.number,
          alert_severity: alert.severity.upcase.to_sym,
          ghsa_id: alert.vulnerability.ghsa_id,
          ecosystem: alert.ecosystem,
          alert_resolution: nil,
        )

        assert_equal [], revision.fields_with_deviation(alert:)

        alert.fix(reason: :DEPENDENCY_CHANGED, push_id: 123)
        assert_equal [:alert_resolved, :alert_resolution], revision.fields_with_deviation(alert:)
      end
    end

    context ".upsert_revision" do
      test "inserts new revisions when there are no previous revisions for an alert" do
        Timecop.freeze do
          alert_number = 1
          repository_id = @repo.id

          refute DependabotAlertRevision.any?

          payload = update_payload
          DependabotAlertRevision.upsert_revision(payload, repository_id:, alert_number:)
          assert_equal 1, DependabotAlertRevision.count

          assert_revision_fields(
            T.must(DependabotAlertRevision.first),
            update_payload: payload,
            repository_id:,
            alert_number:,
            next_revision_date_id: Date::FUTURE_DATE_ID,
          )
        end
      end

      test "inserts newer revisions at the end of an alert's revision chain and updates the previous revision's pointer" do
        time = Time.new(2020, 4, 3, 0, 10, 0)
        alert_number = 1
        repository_id = @repo.id

        Timecop.freeze(time) do
          prev_time = 2.days.ago
          prev_date_id = Date.id_from_time(prev_time)
          prev_update_payload = update_payload(alert_created_at: prev_time, alert_updated_at: prev_time)
          create(
            :soa_dependabot_alert_revision,
            repository_id:,
            alert_number:,
            date_id: prev_date_id,
            alert_created_at: prev_time,
            alert_updated_at: prev_time,
          )
          new_record_date_id = Date.id_from_time(time)
          update_payload = update_payload(alert_created_at: prev_time, alert_updated_at: time)

          assert_equal 1, DependabotAlertRevision.count
          DependabotAlertRevision.upsert_revision(update_payload, repository_id:, alert_number:)
          assert_equal 2, DependabotAlertRevision.count

          # new record
          assert_revision_fields(
            T.must(DependabotAlertRevision.find_by(date_id: new_record_date_id)),
            update_payload:,
            repository_id:,
            alert_number:,
            next_revision_date_id: Date::FUTURE_DATE_ID,
          )

          # previous record
          assert_revision_fields(
            T.must(DependabotAlertRevision.find_by(date_id: prev_date_id)),
            update_payload: T.must(prev_update_payload),
            repository_id:,
            alert_number:,
            next_revision_date_id: new_record_date_id,
          )
        end
      end

      test "updates existing revisions for an alert with newer info" do
        time = Time.new(2020, 4, 1, 0, 10, 0)
        alert_number = 1
        repository_id = @repo.id

        Timecop.freeze(time) do
          alert_created_at = Time.now.ago(1.minute)

          prev_payload = update_payload(alert_created_at:, alert_updated_at: Time.now.ago(1.minute))
          create(:soa_dependabot_alert_revision, repository_id:, alert_number:, alert_updated_at: prev_payload.alert_updated_at)

          assert_equal 1, DependabotAlertRevision.count
          assert_revision_fields(
            T.must(DependabotAlertRevision.first),
            update_payload: prev_payload,
            repository_id:,
            alert_number:,
            next_revision_date_id: Date::FUTURE_DATE_ID,
          )

          new_updated_at = Time.now.since(1.minute)
          new_payload = update_payload(
            alert_created_at:,
            alert_updated_at: new_updated_at,
            alert_resolved: true,
            alert_resolved_at: new_updated_at,
            alert_resolution: Event::LastStateChangeReason::FIX_STARTED,
            alert_severity: :MEDIUM,
            ghsa_id: "GHSA-AAAA-BBBB-CCCC",
            dependency_scope: :DEVELOPMENT,
            package_name: "snackage",
            ecosystem: "yum",
          )
          DependabotAlertRevision.upsert_revision(new_payload, repository_id:, alert_number:)

          assert_equal 1, DependabotAlertRevision.count
          assert_revision_fields(
            T.must(DependabotAlertRevision.first),
            update_payload: new_payload,
            repository_id:,
            alert_number:,
            next_revision_date_id: Date::FUTURE_DATE_ID,
          )
        end
      end

      context "out of order events" do
        test "does not update existing revisions for an alert with outdated info" do
          time = Time.new(2020, 4, 1, 0, 10, 0)
          alert_number = 1
          repository_id = @repo.id

          Timecop.freeze(time) do
            prev_payload = update_payload(alert_updated_at: Time.now.since(1.minute))
            create(:soa_dependabot_alert_revision, repository_id:, alert_number:, alert_updated_at: prev_payload.alert_updated_at)

            assert_equal 1, DependabotAlertRevision.count
            assert_revision_fields(
              T.must(DependabotAlertRevision.first),
              update_payload: prev_payload,
              repository_id:,
              alert_number:,
              next_revision_date_id: Date::FUTURE_DATE_ID,
            )

            new_updated_at = Time.now.ago(1.minute)
            DependabotAlertRevision.upsert_revision(
              update_payload(
                alert_updated_at: new_updated_at,
                alert_resolved: true,
                alert_resolved_at: new_updated_at,
                alert_severity: :LOW,
                package_name: "snackage",
                ecosystem: "yum",
              ),
              repository_id:,
              alert_number:
            )

            assert_equal 1, DependabotAlertRevision.count
            assert_revision_fields(
              T.must(DependabotAlertRevision.first),
              update_payload: prev_payload,
              repository_id:,
              alert_number:,
              next_revision_date_id: Date::FUTURE_DATE_ID,
            )
          end
        end

        test "does not update existing revisions for an alert if updated_at of payload is the same" do
          time = Time.new(2020, 4, 1, 0, 10, 0)
          alert_number = 1
          repository_id = @repo.id

          Timecop.freeze(time) do
            payload = update_payload
            DependabotAlertRevision.upsert_revision(
              payload,
              repository_id:,
              alert_number:
            )
            current_revision = DependabotAlertRevision.find_by(date_id: Date.id_from_time(payload.alert_updated_at), repository_id:, alert_number:)
            assert current_revision
            refute current_revision&.alert_resolved

            new_payload = update_payload(alert_resolved: true)
            DependabotAlertRevision.upsert_revision(
              new_payload,
              repository_id:,
              alert_number:
            )
            refute current_revision&.reload&.alert_resolved
          end
        end

        test "can force rewrite existing revisions with the same update_at timestamp" do
          time = Time.new(2020, 4, 1, 0, 10, 0)
          alert_number = 1
          repository_id = @repo.id

          Timecop.freeze(time) do
            payload = update_payload
            DependabotAlertRevision.upsert_revision(
              payload,
              repository_id:,
              alert_number:
            )
            current_revision = DependabotAlertRevision.find_by(date_id: Date.id_from_time(payload.alert_updated_at), repository_id:, alert_number:)
            assert current_revision
            refute current_revision&.alert_resolved

            # Microsecond precision should be ignored during timestamp comparison.
            new_payload = update_payload(alert_resolved: true, alert_updated_at: time.change(usec: 123))
            DependabotAlertRevision.upsert_revision(
              new_payload,
              repository_id:,
              alert_number:,
              force_rewrite: true
            )
            assert current_revision&.reload&.alert_resolved
          end
        end

        test "inserts older revisions at the beginning of the revision chain for an alert pointed to the next revision" do
          time = Time.new(2020, 4, 3, 0, 10, 0)
          alert_number = 1
          repository_id = @repo.id

          Timecop.freeze(time) do
            earliest_time = 2.days.ago
            latest_revision = create(
              :soa_dependabot_alert_revision,
              repository_id:,
              alert_number:,
              alert_created_at: earliest_time,
              alert_updated_at: time,
            )

            earliest_date_id = Date.id_from_time(earliest_time)
            earliest_update_payload = update_payload(alert_created_at: earliest_time, alert_updated_at: earliest_time)
            assert_equal 1, DependabotAlertRevision.count
            DependabotAlertRevision.upsert_revision(
              earliest_update_payload,
              repository_id:,
              alert_number:
            )
            assert_equal 2, DependabotAlertRevision.count

            # latest record
            latest_date_id = latest_revision.date_id
            assert_revision_fields(
              T.must(DependabotAlertRevision.find_by(date_id: latest_date_id)),
              update_payload: update_payload(alert_created_at: earliest_time, alert_updated_at: time),
              repository_id:,
              alert_number:,
              next_revision_date_id: Date::FUTURE_DATE_ID,
            )

            # earliest record
            assert_revision_fields(
              T.must(DependabotAlertRevision.find_by(date_id: earliest_date_id)),
              update_payload: earliest_update_payload,
              repository_id:,
              alert_number:,
              next_revision_date_id: latest_date_id,
            )
          end
        end

        test "creates a new revision between existing revisions" do
          time = Time.new(2020, 4, 3, 0, 10, 0)
          alert_number = 1
          repository_id = @repo.id

          Timecop.freeze(time) do
            earliest_time = 2.days.ago
            earliest_date_id = Date.id_from_time(earliest_time)
            latest_date_id = Date.id_from_time(time)
            earliest_revision = create(
              :soa_dependabot_alert_revision,
              repository_id:,
              alert_number:,
              date_id: earliest_date_id,
              next_revision_date_id: latest_date_id,
              alert_created_at: earliest_time,
              alert_updated_at: earliest_time,
            )
            latest_revision = create(
              :soa_dependabot_alert_revision,
              repository_id:,
              alert_number:,
              date_id: latest_date_id,
              alert_created_at: earliest_time,
              alert_updated_at: time,
            )

            assert_equal 2, DependabotAlertRevision.count
            new_time = 1.day.ago
            DependabotAlertRevision.upsert_revision(
              update_payload(alert_created_at: earliest_time, alert_updated_at: new_time),
              repository_id:,
              alert_number:
            )
            assert_equal 3, DependabotAlertRevision.count

            # latest record
            assert_revision_fields(
              T.must(DependabotAlertRevision.find_by(date_id: latest_date_id)),
              update_payload: update_payload(alert_created_at: earliest_time, alert_updated_at: time),
              repository_id:,
              alert_number:,
              next_revision_date_id: Date::FUTURE_DATE_ID,
            )

            # new record
            new_date_id = Date.id_from_time(new_time)
            assert_revision_fields(
              T.must(DependabotAlertRevision.find_by(date_id: new_date_id)),
              update_payload: update_payload(alert_created_at: earliest_time, alert_updated_at: new_time),
              repository_id:,
              alert_number:,
              next_revision_date_id: latest_date_id,
            )

            # earliest record
            assert_revision_fields(
              T.must(DependabotAlertRevision.find_by(date_id: earliest_date_id)),
              update_payload: update_payload(alert_created_at: earliest_time, alert_updated_at: earliest_time),
              repository_id:,
              alert_number:,
              next_revision_date_id: new_date_id,
            )
          end
        end
      end
    end

    context ".update_severities" do
      test "updates all existing revisions with new severity" do
        repository_id = @repo.id
        alert_number = 1

        create(:soa_dependabot_alert_revision, repository_id:, alert_number:, date_id: 20240101, next_revision_date_id: 20240103, alert_severity: :MODERATE)
        create(:soa_dependabot_alert_revision, repository_id:, alert_number:, date_id: 20240103, next_revision_date_id: 20240105, alert_severity: :MODERATE)
        create(:soa_dependabot_alert_revision, repository_id:, alert_number:, date_id: 20240105, next_revision_date_id: 99991231, alert_severity: :MODERATE)

        assert_equal 3, DependabotAlertRevision.count
        DependabotAlertRevision.update_severities(:CRITICAL, repository_id:, alert_number:)
        assert_equal 3, DependabotAlertRevision.count

        DependabotAlertRevision.where(repository_id:, alert_number:).each do |revision|
          assert_equal "CRITICAL", revision.alert_severity
        end

        assert_dogstats_count_value 3, "security_overview_analytics.dependabot_alert_revisions.severities_updated"
      end
    end

    context ".create_update_payload" do
      context "validates event payload" do
        test "raises error if created_at is missing" do
          event = event_payload({ created_at: nil })
          assert_raises_with_message(RuntimeError, "Missing created_at in RepositoryVulnerabilityAlertLifecycleEvent payload") do
            DependabotAlertRevision.create_update_payload(event)
          end
        end

        test "raises error if updated_at is missing" do
          event = event_payload({ updated_at: nil })
          assert_raises_with_message(RuntimeError, "Missing updated_at in RepositoryVulnerabilityAlertLifecycleEvent payload") do
            DependabotAlertRevision.create_update_payload(event)
          end
        end

        test "raises error if severity is an integer" do
          event = event_payload({ severity: 123 })
          assert_raises_with_message(RuntimeError, "Unknown RepositoryVulnerabilityAlertLifecycleEvent::Severity enum value: 123") do
            DependabotAlertRevision.create_update_payload(event)
          end
        end

        test "raises error if dependency_scope is an integer" do
          event = event_payload({ dependency_scope: 123 })
          assert_raises_with_message(RuntimeError, "Unknown RepositoryVulnerabilityAlertLifecycleEvent::DependencyScope enum value: 123") do
            DependabotAlertRevision.create_update_payload(event)
          end
        end

        test "alert_resolved is false if state is open" do
          event = event_payload({ state: :OPEN })
          refute DependabotAlertRevision.create_update_payload(event).alert_resolved
        end

        test "alert_resolved_at is present if alert is resolved" do
          event = event_payload({ state: :FIXED, last_state_change_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i) })
          assert DependabotAlertRevision.create_update_payload(event).alert_resolved_at
        end
      end
    end

    context "#delete_by_repository_ids" do
      test "deletes all revisions on a repository" do
        now = Time.now
        repository_id = @repo.id
        alert_number = 1

        [
          create(:security_overview_analytics_date, date_value: now),
          create(:security_overview_analytics_date, date_value: now - 1.day)
        ].reduce(Date::FUTURE_DATE_ID) do |next_date_id, date|
          create(
            :soa_dependabot_alert_revision,
            repository_id:,
            alert_number: alert_number += 1,
            date: date,
            next_revision_date_id: next_date_id,
          )
          create(
            :soa_dependabot_alert_revision,
            repository_id: repository_id + 1,
            alert_number: alert_number += 1,
            date: date,
            next_revision_date_id: next_date_id,
          )
          create(
            :soa_dependabot_alert_revision,
            repository_id: repository_id + 2,
            alert_number: alert_number += 1,
            date: date,
            next_revision_date_id: next_date_id,
          )
          next date.id
        end
        repo1_alert_numbers = DependabotAlertRevision.where(repository_id: repository_id).pluck(:alert_number).uniq
        repo2_alert_numbers = DependabotAlertRevision.where(repository_id: repository_id + 1).pluck(:alert_number).uniq
        repo3_alert_numbers = DependabotAlertRevision.where(repository_id: repository_id + 2).pluck(:alert_number).uniq
        assert_equal 2, repo1_alert_numbers.size
        assert_equal 2, repo2_alert_numbers.size
        assert_equal 2, repo3_alert_numbers.size

        DependabotAlertRevision.delete_by_repository_ids([repository_id, repository_id + 1])

        assert_empty DependabotAlertRevision.where(repository_id: [repository_id, repository_id + 1]).to_a
        assert_dogstats_count_value 4, "security_overview_analytics.dependabot_alert_revisions.deleted"

        repo3_alert_numbers = DependabotAlertRevision.where(repository_id: repository_id + 2).pluck(:alert_number).uniq
        assert_equal 2, repo3_alert_numbers.size
      end
    end

    context "#update_feature_status_summary" do
      test "enqueues job" do
        model = T.let(create(:soa_dependabot_alert_revision), DependabotAlertRevision)

        UpdateFeatureStatusSummaryJob
          .expects(:enqueue_once_per_interval)
          .with do |**options|
            options.dig(:kwargs, :repository_id) == model.repository_id &&
            options.dig(:interval) == 30
          end
          .once

        model.update_feature_status_summary
      end

      test "invoked on commit" do
        model = T.let(create(:soa_dependabot_alert_revision), DependabotAlertRevision)

        UpdateFeatureStatusSummaryJob
          .expects(:enqueue_once_per_interval)
          .with do |**options|
            options.dig(:kwargs, :repository_id) == model.repository_id &&
            options.dig(:interval) == 30
          end
          .once

        model.alert_resolved = true
        model.save
      end

      context "when not latest revision" do
        test "does not enqueue summary upsert job" do
          model = T.let(create(:soa_dependabot_alert_revision, next_revision_date_id: 20240101), DependabotAlertRevision)

          UpdateFeatureStatusSummaryJob
            .expects(:enqueue_once_per_interval)
            .never

          model.update_feature_status_summary
        end
      end
    end

    private

    sig { params(override: T::Hash[Symbol, T.untyped]).returns(Event) }
    def event_payload(override)
      Event.new(
        {
          state: :OPEN,
          last_state_change_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i),
          severity: :LOW,
          dependency_scope: :RUNTIME,
          package_name: "package.json",
          ecosystem: "npm",
          created_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i),
          updated_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i)
        }.merge(override)
      )
    end

    sig { params(kwargs: T.untyped).returns(DependabotAlertRevision::UpdatePayload) }
    def update_payload(**kwargs)
      t = Time.now

      update_payload_kwargs = {
        alert_resolved: false,
        alert_resolved_at: nil,
        alert_resolution: nil,
        alert_severity: :LOW,
        ghsa_id: "GHSA-1234-5678-90AB",
        dependency_scope: :RUNTIME,
        package_name: "react",
        ecosystem: "npm",
        alert_created_at: t,
        alert_updated_at: t,
        **kwargs,
      }

      DependabotAlertRevision::UpdatePayload.new(**T.unsafe(update_payload_kwargs))
    end

    sig { params(revision: DependabotAlertRevision, update_payload: DependabotAlertRevision::UpdatePayload, repository_id: Integer, alert_number: Integer, next_revision_date_id: Integer).void }
    def assert_revision_fields(revision, update_payload:, repository_id:, alert_number:, next_revision_date_id:)
      date_id = Date.id_from_time(update_payload.alert_updated_at)

      assert_equal repository_id, revision.repository_id, "repository ID"
      assert_equal alert_number, revision.alert_number, "alert number"
      assert_equal date_id, revision.date_id, "date ID"
      assert_equal next_revision_date_id, revision.next_revision_date_id, "next revision date ID"

      assert update_payload.alert_created_at.to_time.minus_with_coercion(revision.alert_created_at) <= 1, "created at"
      assert update_payload.alert_updated_at.to_time.minus_with_coercion(revision.alert_updated_at) <= 1, "updated at"
      update_payload.alert_resolved_at.tap do |expected|
        actual = revision.alert_resolved_at
        if expected.nil?
          assert_nil actual, "resolved at"
        else
          refute_nil actual, "resolved at"
          assert expected.to_time.minus_with_coercion(actual) <= 1, "resolved at"
        end
      end

      update_payload.alert_resolution.tap do |expected|
        actual = revision.alert_resolution
        if expected.nil?
          assert_nil actual, "resolution"
        else
          refute_nil actual, "resolution"
          assert_equal expected, actual, "resolution"
        end
      end

      assert_equal update_payload.ghsa_id, revision.ghsa_id, "GHSA ID"
      assert_equal update_payload.dependency_scope.to_s.upcase, revision.dependency_scope, "dependency scope"
      assert_equal update_payload.ecosystem, revision.ecosystem, "ecosystem"
      assert_equal update_payload.package_name, revision.package_name, "package"
      assert_equal update_payload.alert_resolved, revision.alert_resolved, "resolved?"
      assert_equal update_payload.alert_severity.to_s.upcase, revision.alert_severity&.upcase, "severity"
    end
  end
end
