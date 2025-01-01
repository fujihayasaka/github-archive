# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class CodeScanningAlertRevisionTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers
    include SecurityCenter::TestHelpers

    CodeScanningResolutions = ::Turboscan::Proto::ResultResolution

    fixtures do
      @org = create(:business_plus_organization)
      @repo = create(:repository, :minimal, owner: @org)
      @soa_repo = create(:security_overview_analytics_repository, repository: @repo)
    end

    context ".write_alert_number?" do
      test "returns true in dotcom", skip_enterprise: true do
        assert CodeScanningAlertRevision.write_alert_number?
      end

      test "returns false in enterprise", enterprise_only: true do
        refute CodeScanningAlertRevision.write_alert_number?
      end
    end

    context ".to_closure_reasons" do
      test "returns the closure reasons mapped to fixed_or_revoked" do
        reasons = CodeScanningAlertRevision.to_closure_reasons([:fixed_or_revoked])
        assert_equal reasons, CodeScanningAlertRevision::RESOLUTIONS_MAPPING[:fixed_or_revoked]
      end

      test "returns the closure reasons mapped to false_positive" do
        reasons = CodeScanningAlertRevision.to_closure_reasons([:false_positive])
        assert_equal reasons, CodeScanningAlertRevision::RESOLUTIONS_MAPPING[:false_positive]
      end

      test "returns the closure reasons mapped to risk_accepted" do
        reasons = CodeScanningAlertRevision.to_closure_reasons([:risk_accepted])
        assert_equal reasons, CodeScanningAlertRevision::RESOLUTIONS_MAPPING[:risk_accepted]
      end

      test "returns the closure reasons mapped to multiple filters" do
        reasons = CodeScanningAlertRevision.to_closure_reasons([:fixed_or_revoked, :risk_accepted])
        mapped_reasons = [CodeScanningAlertRevision::RESOLUTIONS_MAPPING[:fixed_or_revoked], CodeScanningAlertRevision::RESOLUTIONS_MAPPING[:risk_accepted]].flatten
        assert_equal reasons, mapped_reasons
      end
    end

    context "#upsert_revision" do
      test "inserts new revisions when there are no previous revisions for an alert" do
        alert_number = 1
        repository_id = @repo.id

        refute CodeScanningAlertRevision.any?
        CodeScanningAlertRevision.upsert_revision(update_payload, repository_id:, alert_number:)
        assert_equal 1, CodeScanningAlertRevision.count

        assert_revision_fields(
          T.must(CodeScanningAlertRevision.first),
          payload: update_payload,
          repository_id:,
          alert_number:,
          next_revision_date_id: Date::FUTURE_DATE_ID,
        )
      end

      test "inserts newer revisions at the end of an alert's revision chain and updates the previous revision's pointer" do
        time = Time.new(2020, 4, 3, 0, 10, 0)
        alert_number = 1
        repository_id = @repo.id

        Timecop.freeze(time) do
          prev_time = 2.days.ago
          prev_date_id = Date.id_from_time(prev_time)

          prev_update_payload = update_payload(alert_created_at: prev_time, alert_updated_at: prev_time)
          create(:soa_code_scanning_alert_revision, repository_id:, date_id: prev_date_id, alert_number:, alert_created_at: prev_time, alert_updated_at: prev_time)
          assert_equal 1, CodeScanningAlertRevision.count

          new_payload = update_payload(alert_created_at: prev_time)
          CodeScanningAlertRevision.upsert_revision(new_payload, repository_id:, alert_number:)
          assert_equal 2, CodeScanningAlertRevision.count

          # new record
          new_record_date_id = Date.id_from_time(new_payload.alert_updated_at)
          assert_revision_fields(
            T.must(CodeScanningAlertRevision.find_by(date_id: new_record_date_id)),
            payload: new_payload,
            repository_id:,
            alert_number:,
            next_revision_date_id: Date::FUTURE_DATE_ID,
          )

          # previous record
          assert_revision_fields(
            T.must(CodeScanningAlertRevision.find_by(date_id: prev_date_id)),
            payload: T.must(prev_update_payload),
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
          prev_payload = update_payload(alert_updated_at: Time.now.ago(1.minute))
          create(:soa_code_scanning_alert_revision, repository_id:, alert_number:, alert_created_at: prev_payload.alert_created_at, alert_updated_at: prev_payload.alert_updated_at)

          assert_equal 1, CodeScanningAlertRevision.count
          assert_revision_fields(
            T.must(CodeScanningAlertRevision.first),
            payload: prev_payload,
            repository_id:,
            alert_number:,
            next_revision_date_id: Date::FUTURE_DATE_ID,
          )

          new_updated_at = Time.now.since(1.minute)
          new_payload = update_payload(
            alert_updated_at: new_updated_at,
            alert_resolved: true,
            alert_resolved_at: new_updated_at,
            alert_severity: "low",
            tool: "CodeQL",
            rule_sarif_identifier: "java/xss",
            language: "Java",
            ref: "develop",
          )
          CodeScanningAlertRevision.upsert_revision(new_payload, repository_id:, alert_number:)

          assert_equal 1, CodeScanningAlertRevision.count
          assert_revision_fields(
            T.must(CodeScanningAlertRevision.first),
            payload: new_payload,
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
            create(:soa_code_scanning_alert_revision, repository_id:, alert_number:, alert_created_at: prev_payload.alert_created_at, alert_updated_at: prev_payload.alert_updated_at)

            assert_equal 1, CodeScanningAlertRevision.count
            assert_revision_fields(
              T.must(CodeScanningAlertRevision.first),
              payload: prev_payload,
              repository_id:,
              alert_number:,
              next_revision_date_id: Date::FUTURE_DATE_ID,
            )

            new_updated_at = Time.now.ago(1.minute)
            CodeScanningAlertRevision.upsert_revision(
              update_payload(
                alert_updated_at: new_updated_at,
                alert_resolved: true,
                alert_resolved_at: new_updated_at,
                alert_severity: "low",
                tool: "CodeQL",
                rule_sarif_identifier: "java/xss",
                language: "Java",
                ref: "develop",
              ),
              repository_id:,
              alert_number:,
            )

            assert_equal 1, CodeScanningAlertRevision.count
            assert_revision_fields(
              T.must(CodeScanningAlertRevision.first),
              payload: prev_payload,
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
            CodeScanningAlertRevision.upsert_revision(
              payload,
              repository_id:,
              alert_number:,
            )
            current_revision = CodeScanningAlertRevision.find_by(date_id: Date.id_from_time(payload.alert_updated_at), repository_id:, alert_number:)
            assert current_revision
            refute current_revision&.alert_resolved

            new_payload = update_payload(alert_resolved: true)
            CodeScanningAlertRevision.upsert_revision(
              new_payload,
              repository_id:,
              alert_number:,
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
            CodeScanningAlertRevision.upsert_revision(
              payload,
              repository_id:,
              alert_number:,
            )
            current_revision = CodeScanningAlertRevision.find_by(date_id: Date.id_from_time(payload.alert_updated_at), repository_id:, alert_number:)
            assert current_revision
            refute current_revision&.alert_resolved

            # Microsecond precision should be ignored during timestamp comparison.
            new_payload = update_payload(alert_resolved: true, alert_updated_at: time.change(usec: 123))
            CodeScanningAlertRevision.upsert_revision(
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
              :soa_code_scanning_alert_revision,
              repository_id:,
              alert_number:,
              alert_created_at: earliest_time,
              alert_updated_at: time,
            )

            earliest_date_id = Date.id_from_time(earliest_time)
            earliest_update_payload = update_payload(alert_created_at: earliest_time, alert_updated_at: earliest_time)
            assert_equal 1, CodeScanningAlertRevision.count
            CodeScanningAlertRevision.upsert_revision(
              earliest_update_payload,
              repository_id:,
              alert_number:,
            )
            assert_equal 2, CodeScanningAlertRevision.count

            # latest record
            latest_date_id = latest_revision.date_id
            assert_revision_fields(
              T.must(CodeScanningAlertRevision.find_by(date_id: latest_date_id)),
              payload: update_payload(alert_created_at: earliest_time, alert_updated_at: time),
              repository_id:,
              alert_number:,
              next_revision_date_id: Date::FUTURE_DATE_ID,
            )

            # earliest record
            assert_revision_fields(
              T.must(CodeScanningAlertRevision.find_by(date_id: earliest_date_id)),
              payload: earliest_update_payload,
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
            create(
              :soa_code_scanning_alert_revision,
              repository_id:,
              alert_number:,
              date_id: earliest_date_id,
              next_revision_date_id: latest_date_id,
              alert_created_at: earliest_time,
              alert_updated_at: earliest_time,
            )
            create(
              :soa_code_scanning_alert_revision,
              repository_id:,
              alert_number:,
              date_id: latest_date_id,
              alert_created_at: earliest_time,
              alert_updated_at: time,
            )

            assert_equal 2, CodeScanningAlertRevision.count
            new_time = 1.day.ago
            CodeScanningAlertRevision.upsert_revision(
              update_payload(alert_created_at: earliest_time, alert_updated_at: new_time),
              repository_id:,
              alert_number:,
            )
            assert_equal 3, CodeScanningAlertRevision.count

            # latest record
            assert_revision_fields(
              T.must(CodeScanningAlertRevision.find_by(date_id: latest_date_id)),
              payload: update_payload(alert_created_at: earliest_time, alert_updated_at: time),
              repository_id:,
              alert_number:,
              next_revision_date_id: Date::FUTURE_DATE_ID,
            )

            # new record
            new_date_id = Date.id_from_time(new_time)
            assert_revision_fields(
              T.must(CodeScanningAlertRevision.find_by(date_id: new_date_id)),
              payload: update_payload(alert_created_at: earliest_time, alert_updated_at: new_time),
              repository_id:,
              alert_number:,
              next_revision_date_id: latest_date_id,
            )

            # earliest record
            assert_revision_fields(
              T.must(CodeScanningAlertRevision.find_by(date_id: earliest_date_id)),
              payload: update_payload(alert_created_at: earliest_time, alert_updated_at: earliest_time),
              repository_id:,
              alert_number:,
              next_revision_date_id: new_date_id,
            )
          end
        end
      end
    end

    context "#delete_revisions" do
      test "deletes all revisions for an alert" do
        create(:soa_code_scanning_alert_revision, repository_id: 1, alert_number: 1, date_id: 20231001, next_revision_date_id: 20231002)
        create(:soa_code_scanning_alert_revision, repository_id: 1, alert_number: 1, date_id: 20231002, next_revision_date_id: 20231003)
        create(:soa_code_scanning_alert_revision, repository_id: 1, alert_number: 1, date_id: 20231003, next_revision_date_id: Date::FUTURE_DATE_ID)

        # these should still exist post-action
        create(:soa_code_scanning_alert_revision, repository_id: 1, alert_number: 2, date_id: 20231001, next_revision_date_id: Date::FUTURE_DATE_ID)
        create(:soa_code_scanning_alert_revision, repository_id: 3, alert_number: 3, date_id: 20231002, next_revision_date_id: Date::FUTURE_DATE_ID)

        assert_equal 5, CodeScanningAlertRevision.count

        CodeScanningAlertRevision.delete_revisions(repository_id: 1, alert_number: 1)

        refute CodeScanningAlertRevision.where(repository_id: 1, alert_number: 1).exists?
        assert CodeScanningAlertRevision.where(repository_id: 1, alert_number: 2).exists?
        assert CodeScanningAlertRevision.where(repository_id: 3, alert_number: 3).exists?

        assert_dogstats_count(1, "security_overview_analytics.code_scanning_alert_revisions.deleted")
        assert_dogstats_count_value(3, "security_overview_analytics.code_scanning_alert_revisions.deleted")
      end

      test "deletes all revisions for an alert queried by alert_id if id is present" do
        create(:soa_code_scanning_alert_revision, repository_id: 1, alert_id: 1, alert_number: 5, date_id: 20231001, next_revision_date_id: 20231002)
        create(:soa_code_scanning_alert_revision, repository_id: 1, alert_id: 1, alert_number: 5, date_id: 20231002, next_revision_date_id: 20231003)
        create(:soa_code_scanning_alert_revision, repository_id: 1, alert_id: 1, alert_number: 5, date_id: 20231003, next_revision_date_id: Date::FUTURE_DATE_ID)

        # these should still exist post-action
        create(:soa_code_scanning_alert_revision, repository_id: 1, alert_id: 2, alert_number: 1, date_id: 20231001, next_revision_date_id: Date::FUTURE_DATE_ID)
        create(:soa_code_scanning_alert_revision, repository_id: 3, alert_id: 2, alert_number: 1, date_id: 20231002, next_revision_date_id: Date::FUTURE_DATE_ID)

        assert_equal 5, CodeScanningAlertRevision.count

        CodeScanningAlertRevision.delete_revisions(repository_id: 1, alert_number: 5, alert_id: 1)

        refute CodeScanningAlertRevision.where(repository_id: 1, alert_number: 5).exists?
        assert CodeScanningAlertRevision.where(repository_id: 1, alert_number: 1).exists?
        assert CodeScanningAlertRevision.where(repository_id: 3, alert_number: 1).exists?

        assert_dogstats_count(1, "security_overview_analytics.code_scanning_alert_revisions.deleted")
        assert_dogstats_count_value(3, "security_overview_analytics.code_scanning_alert_revisions.deleted")
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
            :soa_code_scanning_alert_revision,
            repository_id:,
            alert_number: alert_number += 1,
            date: date,
            next_revision_date_id: next_date_id,
          )
          create(
            :soa_code_scanning_alert_revision,
            repository_id: repository_id + 1,
            alert_number: alert_number += 1,
            date: date,
            next_revision_date_id: next_date_id,
          )
          create(
            :soa_code_scanning_alert_revision,
            repository_id: repository_id + 2,
            alert_number: alert_number += 1,
            date: date,
            next_revision_date_id: next_date_id,
          )
          next date.id
        end
        repo1_alert_numbers = CodeScanningAlertRevision.where(repository_id: repository_id).pluck(:alert_number).uniq
        repo2_alert_numbers = CodeScanningAlertRevision.where(repository_id: repository_id + 1).pluck(:alert_number).uniq
        repo3_alert_numbers = CodeScanningAlertRevision.where(repository_id: repository_id + 2).pluck(:alert_number).uniq
        assert_equal 2, repo1_alert_numbers.size
        assert_equal 2, repo2_alert_numbers.size
        assert_equal 2, repo3_alert_numbers.size

        CodeScanningAlertRevision.delete_by_repository_ids([repository_id, repository_id + 1])

        assert_empty CodeScanningAlertRevision.where(repository_id: [repository_id, repository_id + 1]).to_a
        assert_dogstats_count_value 4, "security_overview_analytics.code_scanning_alert_revisions.deleted"

        repo3_alert_numbers = CodeScanningAlertRevision.where(repository_id: repository_id + 2).pluck(:alert_number).uniq
        assert_equal 2, repo3_alert_numbers.size
      end
    end

    context "'==' operator" do
      test "returns true of revisions have identical data except for alert_updated_at`" do
        date1 = create(:security_overview_analytics_date, date_value: Time.parse("2024-08-20"))
        date2 = create(:security_overview_analytics_date, date_value: Time.parse("2024-08-21"))
        rev1 = create(:soa_code_scanning_alert_revision, repository_metadata: @soa_repo, date: date1, next_revision_date_id: date2.id, alert_created_at: date1.date_value, alert_updated_at: date1.date_value)
        rev2 = create(:soa_code_scanning_alert_revision, repository_metadata: @soa_repo, date: date2, next_revision_date_id: Date::FUTURE_DATE_ID, alert_created_at: date1.date_value, alert_updated_at: date2.date_value)
        assert rev1 == rev2
      end

      test "returns false of revisions has different alert_created_at" do
        date1 = create(:security_overview_analytics_date, date_value: Time.parse("2024-08-20"))
        date2 = create(:security_overview_analytics_date, date_value: Time.parse("2024-08-21"))
        rev1 = create(:soa_code_scanning_alert_revision, repository_metadata: @soa_repo, date: date1, next_revision_date_id: date2.id, alert_created_at: date1.date_value)
        rev2 = create(:soa_code_scanning_alert_revision, repository_metadata: @soa_repo, date: date2, next_revision_date_id: Date::FUTURE_DATE_ID, alert_created_at: date2.date_value)
        refute rev1 == rev2
      end

      test "returns false of revisions has different state" do
        date1 = create(:security_overview_analytics_date, date_value: Time.parse("2024-08-20"))
        date2 = create(:security_overview_analytics_date, date_value: Time.parse("2024-08-21"))
        rev1 = create(:soa_code_scanning_alert_revision, alert_resolved: false, repository_metadata: @soa_repo, date: date1, next_revision_date_id: date2.id, alert_created_at: date1.date_value)
        rev2 = create(:soa_code_scanning_alert_revision, alert_resolved: true, repository_metadata: @soa_repo, date: date2, next_revision_date_id: Date::FUTURE_DATE_ID, alert_created_at: date1.date_value)
        refute rev1 == rev2
      end

      test "returns false of revisions has different metadata" do
        date1 = create(:security_overview_analytics_date, date_value: Time.parse("2024-08-20"))
        date2 = create(:security_overview_analytics_date, date_value: Time.parse("2024-08-21"))
        rev1 = create(:soa_code_scanning_alert_revision, tool: "CodeQL", repository_metadata: @soa_repo, date: date1, next_revision_date_id: date2.id, alert_created_at: date1.date_value)
        rev2 = create(:soa_code_scanning_alert_revision, tool: "Woof", repository_metadata: @soa_repo, date: date2, next_revision_date_id: Date::FUTURE_DATE_ID, alert_created_at: date1.date_value)
        refute rev1 == rev2
      end
    end

    context "#update_feature_status_summary" do
      test "enqueues job" do
        model = T.let(create(:soa_code_scanning_alert_revision), CodeScanningAlertRevision)

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
        model = T.let(create(:soa_code_scanning_alert_revision), CodeScanningAlertRevision)

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
          model = T.let(create(:soa_code_scanning_alert_revision, next_revision_date_id: 20240101), CodeScanningAlertRevision)

          UpdateFeatureStatusSummaryJob
            .expects(:enqueue_once_per_interval)
            .never

          model.update_feature_status_summary
        end
      end
    end

    private

    sig { params(kwargs: T.untyped).returns(CodeScanningAlertRevision::UpdatePayload) }
    def update_payload(**kwargs)
      t = Time.now

      update_payload_kwargs = {
        alert_created_at: t,
        alert_updated_at: t,
        alert_severity: "CRITICAL",
        tool: "CodeQL",
        rule_sarif_identifier: "rb/unsafe-deserialization",
        alert_resolved: false,
        alert_resolved_at: nil,
        alert_resolution: nil,
        alert_id: 1,
        has_autofix: false,
        autofix_accepted: false,
        **kwargs,
      }

      CodeScanningAlertRevision::UpdatePayload.new(**T.unsafe(update_payload_kwargs))
    end

    sig do
      params(
        actual: CodeScanningAlertRevision,
        payload: CodeScanningAlertRevision::UpdatePayload,
        repository_id: Integer,
        alert_number: Integer,
        next_revision_date_id: Integer
      ).void
    end
    def assert_revision_fields(actual, payload:, repository_id:, alert_number:, next_revision_date_id:)
      date_id = Date.id_from_time(payload.alert_updated_at)

      assert_equal repository_id, actual.repository_id, "repository ID"
      assert_equal alert_number, actual.alert_number, "alert number"
      assert_equal date_id, actual.date_id, "date ID"
      assert_equal next_revision_date_id, actual.next_revision_date_id, "next revision date ID"

      assert payload.alert_created_at.to_time.minus_with_coercion(actual.alert_created_at) <= 1, "created at"
      assert payload.alert_updated_at.to_time.minus_with_coercion(actual.alert_updated_at) <= 1, "updated at"
      if payload.alert_resolved_at.nil?
        assert_nil actual.alert_resolved_at, "resolved at"
      else
        refute_nil actual.alert_resolved_at, "resolved at"
        assert payload.alert_resolved_at&.to_time.minus_with_coercion(actual.alert_resolved_at) <= 1, "resolved at"
      end

      assert_equal payload.alert_severity, actual.alert_severity, "alert_severity"
      assert_equal payload.tool, actual.tool, "tool"
      assert_equal payload.rule_sarif_identifier, actual.rule_sarif_identifier, "rule_sarif_identifier"
      assert_equal payload.alert_resolved, actual.alert_resolved, "alert_resolved"

      if payload.language.nil?
        assert_nil actual.language, "language"
      else
        refute_nil actual.language, "language"
        assert_equal payload.language, actual.language, "language"
      end

      if payload.ref.nil?
        assert_nil actual.ref, "ref"
      else
        refute_nil actual.ref, "ref"
        assert_equal payload.ref, actual.ref, "ref"
      end

      if payload.alert_resolution.nil?
        assert_nil actual.alert_resolution, "alert_resolution"
      else
        refute_nil actual.alert_resolution, "alert_resolution"
        assert_equal payload.alert_resolution, actual.alert_resolution, "alert_resolution"
      end
    end
  end
end
