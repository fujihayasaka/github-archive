# typed: true
# frozen_string_literal: true

require "test_helper"

require "secret_scanning_proto"

module SecurityOverviewAnalytics
  class SecretScanningAlertRevisionTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers
    include SecurityCenter::TestHelpers

    SecretScanningAlert = ::GitHub::Proto::SecretScanning::Metrics::V1::Alert
    SecretScanningAlertResolution = ::GitHub::Proto::SecretScanning::Types::V1::TokenResolution

    fixtures do
      @org = create(:business_plus_organization)
      @repo = create(:repository, owner: @org)
    end

    context ".to_closure_reasons" do
      test "returns the closure reasons mapped to fixed_or_revoked" do
        reasons = SecretScanningAlertRevision.to_closure_reasons([:fixed_or_revoked])
        assert_equal reasons, SecretScanningAlertRevision::RESOLUTIONS_MAPPING[:fixed_or_revoked]
      end

      test "returns the closure reasons mapped to auto_dismissed" do
        reasons = SecretScanningAlertRevision.to_closure_reasons([:auto_dismissed])
        assert_equal reasons, SecretScanningAlertRevision::RESOLUTIONS_MAPPING[:auto_dismissed]
      end

      test "returns the closure reasons mapped to false_positive" do
        reasons = SecretScanningAlertRevision.to_closure_reasons([:false_positive])
        assert_equal reasons, SecretScanningAlertRevision::RESOLUTIONS_MAPPING[:false_positive]
      end

      test "returns the closure reasons mapped to risk_accepted" do
        reasons = SecretScanningAlertRevision.to_closure_reasons([:risk_accepted])
        assert_equal reasons, SecretScanningAlertRevision::RESOLUTIONS_MAPPING[:risk_accepted]
      end

      test "returns the closure reasons mapped to multiple filters" do
        reasons = SecretScanningAlertRevision.to_closure_reasons([:fixed_or_revoked, :risk_accepted])
        mapped_reasons = [SecretScanningAlertRevision::RESOLUTIONS_MAPPING[:fixed_or_revoked], SecretScanningAlertRevision::RESOLUTIONS_MAPPING[:risk_accepted]].flatten
        assert_equal reasons, mapped_reasons
      end
    end

    context ".to_valid_severities" do
      test "only return 'critical' severity if present" do
        severities = SecretScanningAlertRevision.to_valid_severities(%w[low medium critical])
        assert_equal severities, ["critical"]

        severities = SecretScanningAlertRevision.to_valid_severities(%w[low medium high])
        assert_empty severities
      end
    end

    context ".upsert_revision" do
      test "inserts new revisions when there are no previous revisions for an alert" do
        date_id = Date.id_from_time(Time.now)
        alert_number = 1
        repository_id = @repo.id

        refute SecretScanningAlertRevision.any?
        SecretScanningAlertRevision.upsert_revision(update_payload, repository_id:, alert_number:)
        assert_equal 1, SecretScanningAlertRevision.count

        assert_revision_fields(
          T.must(SecretScanningAlertRevision.first),
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
          date_id = Date.id_from_time(Time.now)

          prev_time = 2.days.ago
          prev_update_payload = T.let(nil, T.nilable(SecretScanningAlertRevision::UpdatePayload))
          Timecop.travel(prev_time) do
            prev_update_payload = update_payload
            create(
              :soa_secret_scanning_alert_revision,
              repository_id:,
              alert_number:,
              alert_type: "cp_1",
              alert_type_provider: "CP",
              alert_type_slug: "custom_pattern",
              alert_created_at: Time.now,
              alert_updated_at: Time.now
            )
          end

          assert_equal 1, SecretScanningAlertRevision.count
          SecretScanningAlertRevision.upsert_revision(update_payload, repository_id:, alert_number:)
          assert_equal 2, SecretScanningAlertRevision.count

          # new record
          new_date_id = date_id
          assert_revision_fields(
            T.must(SecretScanningAlertRevision.find_by(date_id: new_date_id)),
            payload: update_payload,
            repository_id:,
            alert_number:,
            next_revision_date_id: Date::FUTURE_DATE_ID,
          )

          # previous record
          prev_date_id = Date.id_from_time(prev_time)
          assert_revision_fields(
            T.must(SecretScanningAlertRevision.find_by(date_id: prev_date_id)),
            payload: T.must(prev_update_payload),
            repository_id:,
            alert_number:,
            next_revision_date_id: new_date_id,
          )
        end
      end

      test "updates existing revisions for an alert with newer info" do
        time = Time.new(2020, 4, 1, 0, 10, 0)
        alert_number = 1
        repository_id = @repo.id

        Timecop.freeze(time) do
          date_id = Date.id_from_time(Time.now)

          prev_payload = update_payload(alert_updated_at: Time.now.ago(1.minute))
          create(
            :soa_secret_scanning_alert_revision,
            repository_id:,
            alert_number:,
            alert_type: "cp_1",
            alert_type_provider: "CP",
            alert_type_slug: "custom_pattern",
            alert_created_at: prev_payload.alert_created_at,
            alert_updated_at: prev_payload.alert_updated_at
          )

          assert_equal 1, SecretScanningAlertRevision.count
          assert_revision_fields(
            T.must(SecretScanningAlertRevision.first),
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
            alert_type: "cp_1",
            alert_type_provider: "CP",
            alert_type_slug: "custom_pattern",
          )
          SecretScanningAlertRevision.upsert_revision(new_payload, repository_id:, alert_number:)

          assert_equal 1, SecretScanningAlertRevision.count
          assert_revision_fields(
            T.must(SecretScanningAlertRevision.first),
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
            date_id = Date.id_from_time(Time.now)

            prev_payload = update_payload(alert_updated_at: Time.now.since(1.minute))
            create(
              :soa_secret_scanning_alert_revision,
              repository_id:,
              alert_number:,
              alert_type: "cp_1",
              alert_type_provider: "CP",
              alert_type_slug: "custom_pattern",
              alert_created_at: prev_payload.alert_created_at,
              alert_updated_at: prev_payload.alert_updated_at
            )

            assert_equal 1, SecretScanningAlertRevision.count
            assert_revision_fields(
              T.must(SecretScanningAlertRevision.first),
              payload: prev_payload,
              repository_id:,
              alert_number:,
              next_revision_date_id: Date::FUTURE_DATE_ID,
            )

            new_updated_at = Time.now.ago(1.minute)
            SecretScanningAlertRevision.upsert_revision(
              update_payload(
                alert_updated_at: new_updated_at,
                alert_resolved: true,
                alert_resolved_at: new_updated_at,
                alert_type: "cp_1",
                alert_type_provider: "CP",
                alert_type_slug: "custom_pattern",
              ),
              repository_id:,
              alert_number:
            )

            assert_equal 1, SecretScanningAlertRevision.count
            assert_revision_fields(
              T.must(SecretScanningAlertRevision.first),
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
            SecretScanningAlertRevision.upsert_revision(
              payload,
              repository_id:,
              alert_number:
            )
            current_revision = SecretScanningAlertRevision.find_by(date_id: Date.id_from_time(payload.alert_updated_at), repository_id:, alert_number:)
            assert current_revision
            refute current_revision&.alert_resolved

            new_payload = update_payload(alert_resolved: true)
            SecretScanningAlertRevision.upsert_revision(
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
            SecretScanningAlertRevision.upsert_revision(
              payload,
              repository_id:,
              alert_number:
            )
            current_revision = SecretScanningAlertRevision.find_by(date_id: Date.id_from_time(payload.alert_updated_at), repository_id:, alert_number:)
            assert current_revision
            refute current_revision&.alert_resolved

            # Microsecond precision should be ignored during timestamp comparison.
            new_payload = update_payload(alert_resolved: true, alert_updated_at: time.change(usec: 123))
            SecretScanningAlertRevision.upsert_revision(
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
              :soa_secret_scanning_alert_revision,
              repository_id:,
              alert_number:,
              alert_type: "cp_1",
              alert_type_provider: "CP",
              alert_type_slug: "custom_pattern",
              alert_created_at: earliest_time,
              alert_updated_at: time,
            )

            earliest_date_id = Date.id_from_time(earliest_time)
            earliest_update_payload = update_payload(alert_created_at: earliest_time, alert_updated_at: earliest_time)
            assert_equal 1, SecretScanningAlertRevision.count
            SecretScanningAlertRevision.upsert_revision(
              earliest_update_payload,
              repository_id:,
              alert_number:,
            )
            assert_equal 2, SecretScanningAlertRevision.count

            # latest record
            latest_date_id = latest_revision.date_id
            assert_revision_fields(
              T.must(SecretScanningAlertRevision.find_by(date_id: latest_date_id)),
              payload: update_payload(alert_created_at: earliest_time, alert_updated_at: time),
              repository_id:,
              alert_number:,
              next_revision_date_id: Date::FUTURE_DATE_ID,
            )

            # earliest record
            assert_revision_fields(
              T.must(SecretScanningAlertRevision.find_by(date_id: earliest_date_id)),
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
            latest_date_id = Date.id_from_time(time)
            earliest_revision = Timecop.travel(earliest_time) do
              create(
                :soa_secret_scanning_alert_revision,
                repository_id:,
                alert_number:,
                alert_type: "cp_1",
                alert_type_provider: "CP",
                alert_type_slug: "custom_pattern",
                alert_created_at: earliest_time,
                alert_updated_at: earliest_time,
                next_revision_date_id: latest_date_id,
              )
            end
            latest_revision = create(
              :soa_secret_scanning_alert_revision,
              repository_id:,
              alert_number:,
              alert_type: "cp_1",
              alert_type_provider: "CP",
              alert_type_slug: "custom_pattern",
              alert_created_at: earliest_time,
              alert_updated_at: time,
            )

            assert_equal 2, SecretScanningAlertRevision.count
            new_time = 1.day.ago
            SecretScanningAlertRevision.upsert_revision(
              update_payload(alert_created_at: earliest_time, alert_updated_at: new_time),
              repository_id:,
              alert_number:,
            )
            assert_equal 3, SecretScanningAlertRevision.count

            # latest record
            assert_revision_fields(
              T.must(SecretScanningAlertRevision.find_by(date_id: latest_date_id)),
              payload: update_payload(alert_created_at: earliest_time, alert_updated_at: time),
              repository_id:,
              alert_number:,
              next_revision_date_id: Date::FUTURE_DATE_ID,
            )

            # new record
            new_date_id = Date.id_from_time(new_time)
            assert_revision_fields(
              T.must(SecretScanningAlertRevision.find_by(date_id: new_date_id)),
              payload: update_payload(alert_created_at: earliest_time, alert_updated_at: new_time),
              repository_id:,
              alert_number:,
              next_revision_date_id: latest_date_id,
            )

            # earliest record
            earliest_date_id = Date.id_from_time(earliest_time)
            assert_revision_fields(
              T.must(SecretScanningAlertRevision.find_by(date_id: earliest_date_id)),
              payload: update_payload(alert_created_at: earliest_time, alert_updated_at: earliest_time),
              repository_id:,
              alert_number:,
              next_revision_date_id: new_date_id,
            )
          end
        end
      end
    end

    context ".upsert_revision_with_fields" do
      test "does not upsert if initial revision doesn't exist yet" do
        t = DateTime.new(2024, 1, 1).to_time.utc
        date_id = Date.id_from_time(t)

        fields = {
          alert_validity: 1,
          alert_updated_at: t,
        }

        assert_equal 0, SecretScanningAlertRevision.count
        SecretScanningAlertRevision.upsert_revision_with_fields(fields, repository_id: @repo.id, alert_number: 1)
        assert_equal 0, SecretScanningAlertRevision.count
      end

      test "upserts a new revision with the updated fields if previous revision date_id < event_date_id" do
        t1 = DateTime.new(2024, 1, 1).to_time.utc
        date_id = Date.id_from_time(t1)
        t2 = DateTime.new(2024, 3, 1).to_time.utc
        new_date_id = Date.id_from_time(t2)

        create(
          :soa_secret_scanning_alert_revision,
          date_id:,
          repository_id: @repo.id,
          alert_number: 1,
          alert_type: "cp_1",
          alert_type_provider: "CP",
          alert_type_slug: "custom_pattern",
          alert_created_at: t1,
          alert_updated_at: t1,
          alert_validity: 0,
          alert_bypassed: false,
          next_revision_date_id: Date::FUTURE_DATE_ID,
        )

        fields = {
          alert_validity: 1,
          alert_updated_at: t2,
        }

        assert_equal 1, SecretScanningAlertRevision.count

        SecretScanningAlertRevision.upsert_revision_with_fields(fields, repository_id: @repo.id, alert_number: 1)

        assert_equal 2, SecretScanningAlertRevision.count

        # existing record
        expected_existing_payload = {
          alert_type: "cp_1",
          alert_type_provider: "CP",
          alert_type_slug: "custom_pattern",
          alert_created_at: t1,
          alert_updated_at: t1,
          alert_validity: 0,
          alert_bypassed: false,
          alert_validity_updated_at: nil
        }
        assert_revision_fields(
          T.must(SecretScanningAlertRevision.find_by(date_id:)),
          payload: update_payload(**expected_existing_payload),
          repository_id: @repo.id,
          alert_number: 1,
          next_revision_date_id: new_date_id,
        )
        # new record
        expected_new_payload = {
          alert_type: "cp_1",
          alert_type_provider: "CP",
          alert_type_slug: "custom_pattern",
          alert_created_at: t1,
          alert_updated_at: t2,
          alert_validity: 1,
          alert_bypassed: false,
          alert_validity_updated_at: t2
        }
        assert_revision_fields(
          T.must(SecretScanningAlertRevision.find_by(date_id: new_date_id)),
          payload: update_payload(**expected_new_payload),
          repository_id: @repo.id,
          alert_number: 1,
          next_revision_date_id: Date::FUTURE_DATE_ID,
        )
      end

      test "updates the existing revision if previous revision date_id == event_date_id" do
        t1 = DateTime.new(2024, 1, 1).to_time.utc
        date_id = Date.id_from_time(t1)
        t2 = (t1 + 1.hour)
        new_date_id = Date.id_from_time(t2)

        create(
          :soa_secret_scanning_alert_revision,
          date_id:,
          repository_id: @repo.id,
          alert_number: 1,
          alert_type: "cp_1",
          alert_type_provider: "CP",
          alert_type_slug: "custom_pattern",
          alert_created_at: t1,
          alert_updated_at: t1,
          alert_validity: 0,
          alert_bypassed: false,
          next_revision_date_id: Date::FUTURE_DATE_ID,
        )

        fields = {
          alert_validity: 1,
          alert_updated_at: t2,
        }

        assert_equal 1, SecretScanningAlertRevision.count

        SecretScanningAlertRevision.upsert_revision_with_fields(fields, repository_id: @repo.id, alert_number: 1)

        assert_equal 1, SecretScanningAlertRevision.count

        # existing record
        expected_existing_payload = {
          alert_type: "cp_1",
          alert_type_provider: "CP",
          alert_type_slug: "custom_pattern",
          alert_created_at: t1,
          alert_updated_at: t2,
          alert_validity: 1,
          alert_bypassed: false,
          alert_validity_updated_at: t2
        }
        assert_revision_fields(
          T.must(SecretScanningAlertRevision.find_by(date_id:)),
          payload: update_payload(**expected_existing_payload),
          repository_id: @repo.id,
          alert_number: 1,
          next_revision_date_id: Date::FUTURE_DATE_ID,
        )
      end
    end

    context ".delete_alert_revisions" do
      test "deletes all revisions for an alert" do
        now = Time.now
        alert_number = 1
        repository_id = @repo.id

        [
          create(:security_overview_analytics_date, date_value: now),
          create(:security_overview_analytics_date, date_value: now - 1.day)
        ].reduce(Date::FUTURE_DATE_ID) do |next_date_id, date|
          create(
            :soa_secret_scanning_alert_revision,
            repository_id:,
            alert_number:,
            date: date,
            next_revision_date_id: next_date_id,
          )
          next date.id
        end
        assert_equal 2, SecretScanningAlertRevision.where(repository_id: repository_id, alert_number: alert_number).size

        SecretScanningAlertRevision.delete_alert_revisions(repository_id:, alert_number:)

        assert_empty SecretScanningAlertRevision.where(repository_id: repository_id, alert_number: alert_number).to_a
        assert_dogstats_count_value 2, "security_overview_analytics.secret_scanning_alert_revisions.deleted"
      end
    end

    context ".delete_alerts" do
      test "deletes all revisions for multiple alerts" do
        now = Time.now
        repository_id = @repo.id
        alert_number = 1

        [
          create(:security_overview_analytics_date, date_value: now),
          create(:security_overview_analytics_date, date_value: now - 1.day)
        ].reduce(Date::FUTURE_DATE_ID) do |next_date_id, date|
          create(
            :soa_secret_scanning_alert_revision,
            repository_id:,
            alert_number: alert_number += 1,
            date: date,
            next_revision_date_id: next_date_id,
          )
          next date.id
        end
        alert_numbers = SecretScanningAlertRevision.where(repository_id: repository_id).pluck(:alert_number).uniq
        assert_equal 2, alert_numbers.size

        SecretScanningAlertRevision.delete_alerts(repository_id:, alert_numbers:)

        assert_empty SecretScanningAlertRevision.where(repository_id: repository_id).to_a
        assert_dogstats_count_value 2, "security_overview_analytics.secret_scanning_alert_revisions.deleted"
      end
    end

    context ".delete_by_repository_ids" do
      test "deletes all revisions on a repository" do
        now = Time.now
        repository_id = @repo.id
        alert_number = 1

        [
          create(:security_overview_analytics_date, date_value: now),
          create(:security_overview_analytics_date, date_value: now - 1.day)
        ].reduce(Date::FUTURE_DATE_ID) do |next_date_id, date|
          create(
            :soa_secret_scanning_alert_revision,
            repository_id:,
            alert_number: alert_number += 1,
            date: date,
            next_revision_date_id: next_date_id,
          )
          create(
            :soa_secret_scanning_alert_revision,
            repository_id: repository_id + 1,
            alert_number: alert_number += 1,
            date: date,
            next_revision_date_id: next_date_id,
          )
          create(
            :soa_secret_scanning_alert_revision,
            repository_id: repository_id + 2,
            alert_number: alert_number += 1,
            date: date,
            next_revision_date_id: next_date_id,
          )
          next date.id
        end
        repo1_alert_numbers = SecretScanningAlertRevision.where(repository_id: repository_id).pluck(:alert_number).uniq
        repo2_alert_numbers = SecretScanningAlertRevision.where(repository_id: repository_id + 1).pluck(:alert_number).uniq
        repo3_alert_numbers = SecretScanningAlertRevision.where(repository_id: repository_id + 2).pluck(:alert_number).uniq
        assert_equal 2, repo1_alert_numbers.size
        assert_equal 2, repo2_alert_numbers.size
        assert_equal 2, repo3_alert_numbers.size

        SecretScanningAlertRevision.delete_by_repository_ids([repository_id, repository_id + 1])

        assert_empty SecretScanningAlertRevision.where(repository_id: [repository_id, repository_id + 1]).to_a
        assert_dogstats_count_value 4, "security_overview_analytics.secret_scanning_alert_revisions.deleted"

        repo3_alert_numbers = SecretScanningAlertRevision.where(repository_id: repository_id + 2).pluck(:alert_number).uniq
        assert_equal 2, repo3_alert_numbers.size
      end
    end

    context "alert_validity_will_change" do
      test "assigns default value of alert_validity to 0" do
        new_rev = SecretScanningAlertRevision.new

        assert_equal [0, 0], new_rev.alert_validity_change
      end
    end

    context "#fields_with_deviation" do
      test "returns empty array if there is no deviation" do
        alert_revision = create(
          :soa_secret_scanning_alert_revision,
          repository_id: @repo.id,
          alert_number: 1,
          alert_type: "cp_1",
          alert_type_provider: "CP",
          alert_type_slug: "custom_pattern",
          alert_resolved: false,
          alert_resolved_at: nil,
          alert_resolution: nil,
          alert_validity: 0,
        )
        alert = SecretScanningAlert.new(
          repository_id: alert_revision.repository_id,
          number: alert_revision.alert_number,
          token_type: alert_revision.alert_type,
          token_type_provider: alert_revision.alert_type_provider,
          slug: alert_revision.alert_type_slug,
          resolved: alert_revision.alert_resolved,
          validity: 0,
          resolved_at: \
            if alert_revision.alert_resolved_at.present?
              Google::Protobuf::Timestamp.new(seconds: alert_revision.alert_resolved_at.to_i, nanos: alert_revision.alert_resolved_at.nsec)
            end,
          resolution: \
            if alert_revision.alert_resolution.present?
              SecretScanningAlertResolution.lookup(alert_revision.alert_resolution)
            end,
        )
        assert alert_revision.fields_with_deviation(alert).empty?
      end

      [:alert_type, :alert_type_provider, :alert_type_slug].each do |field|
        test "returns #{field} if it is deviated" do
          alert_revision = create(
            :soa_secret_scanning_alert_revision,
            repository_id: @repo.id,
            alert_number: 1,
            alert_type: "cp_1",
            alert_type_provider: "CP",
            alert_type_slug: "custom_pattern",
            alert_resolved: false,
            alert_resolved_at: nil,
            alert_resolution: nil,
            alert_validity: 0,
          )
          alert = SecretScanningAlert.new(
            repository_id: alert_revision.repository_id,
            number: alert_revision.alert_number,
            token_type: alert_revision.alert_type,
            token_type_provider: alert_revision.alert_type_provider,
            slug: alert_revision.alert_type_slug,
            resolved: alert_revision.alert_resolved,
            validity: 0,
            resolved_at: \
              if alert_revision.alert_resolved_at.present?
                Google::Protobuf::Timestamp.new(seconds: alert_revision.alert_resolved_at.to_i, nanos: alert_revision.alert_resolved_at.nsec)
              end,
            resolution: \
              if alert_revision.alert_resolution.present?
                SecretScanningAlertResolution.lookup(alert_revision.alert_resolution)
              end,
          )
          alert_revision.update({ field => "changed" })
          assert_equal [field], alert_revision.fields_with_deviation(alert)
        end
      end

      test "returns alert_resolved if it is deviated" do
        alert_revision = create(
          :soa_secret_scanning_alert_revision,
          repository_id: @repo.id,
          alert_number: 1,
          alert_type: "cp_1",
          alert_type_provider: "CP",
          alert_type_slug: "custom_pattern",
          alert_resolved: false,
          alert_resolved_at: nil,
          alert_resolution: nil,
          alert_validity: 0,
        )
        alert = SecretScanningAlert.new(
          repository_id: alert_revision.repository_id,
          number: alert_revision.alert_number,
          token_type: alert_revision.alert_type,
          token_type_provider: alert_revision.alert_type_provider,
          slug: alert_revision.alert_type_slug,
          resolved: alert_revision.alert_resolved,
          validity: 0,
          resolved_at: \
            if alert_revision.alert_resolved_at.present?
              Google::Protobuf::Timestamp.new(seconds: alert_revision.alert_resolved_at.to_i, nanos: alert_revision.alert_resolved_at.nsec)
            end,
          resolution: \
            if alert_revision.alert_resolution.present?
              SecretScanningAlertResolution.lookup(alert_revision.alert_resolution)
            end,
        )
        alert_revision.update(alert_resolved: true)
        assert_equal [:alert_resolved], alert_revision.fields_with_deviation(alert)
      end

      test "returns alert_resolved_at if it is deviated" do
        alert_revision = create(
          :soa_secret_scanning_alert_revision,
          repository_id: @repo.id,
          alert_number: 1,
          alert_type: "cp_1",
          alert_type_provider: "CP",
          alert_type_slug: "custom_pattern",
          alert_resolved: true,
          alert_resolved_at: nil,
          alert_resolution: nil,
          alert_validity: 0,
        )
        alert = SecretScanningAlert.new(
          repository_id: alert_revision.repository_id,
          number: alert_revision.alert_number,
          token_type: alert_revision.alert_type,
          token_type_provider: alert_revision.alert_type_provider,
          slug: alert_revision.alert_type_slug,
          resolved: alert_revision.alert_resolved,
          validity: 0,
          resolved_at: \
            if alert_revision.alert_resolved_at.present?
              Google::Protobuf::Timestamp.new(seconds: alert_revision.alert_resolved_at.to_i, nanos: alert_revision.alert_resolved_at.nsec)
            end,
          resolution: \
            if alert_revision.alert_resolution.present?
              SecretScanningAlertResolution.lookup(alert_revision.alert_resolution)
            end,
        )
        alert_revision.update(alert_resolved_at: Time.now)
        assert_equal [:alert_resolved_at], alert_revision.fields_with_deviation(alert)
      end

      test "returns alert_resolution if it is deviated" do
        alert_revision = create(
          :soa_secret_scanning_alert_revision,
          repository_id: @repo.id,
          alert_number: 1,
          alert_type: "cp_1",
          alert_type_provider: "CP",
          alert_type_slug: "custom_pattern",
          alert_resolved: true,
          alert_resolved_at: Time.now,
          alert_resolution: 2,
          alert_validity: 0,
        )
        alert = SecretScanningAlert.new(
          repository_id: alert_revision.repository_id,
          number: alert_revision.alert_number,
          token_type: alert_revision.alert_type,
          token_type_provider: alert_revision.alert_type_provider,
          slug: alert_revision.alert_type_slug,
          resolved: alert_revision.alert_resolved,
          validity: 0,
          resolved_at: \
            if alert_revision.alert_resolved_at.present?
              Google::Protobuf::Timestamp.new(seconds: alert_revision.alert_resolved_at.to_i, nanos: alert_revision.alert_resolved_at.nsec)
            end,
          resolution: \
            if alert_revision.alert_resolution.present?
              SecretScanningAlertResolution.lookup(alert_revision.alert_resolution)
            end,
        )
        alert_revision.update(alert_resolution: 1)
        assert_equal [:alert_resolution], alert_revision.fields_with_deviation(alert)
      end

      test "returns alert_bypassed if it is deviated" do
        alert_revision = create(
          :soa_secret_scanning_alert_revision,
          repository_id: @repo.id,
          alert_number: 1,
          alert_type: "cp_1",
          alert_type_provider: "CP",
          alert_type_slug: "custom_pattern",
          alert_resolved: true,
          alert_resolved_at: Time.now,
          alert_resolution: 2,
          alert_bypassed: false,
          alert_validity: 0,
        )
        alert = SecretScanningAlert.new(
          repository_id: alert_revision.repository_id,
          number: alert_revision.alert_number,
          token_type: alert_revision.alert_type,
          token_type_provider: alert_revision.alert_type_provider,
          slug: alert_revision.alert_type_slug,
          resolved: alert_revision.alert_resolved,
          validity: 0,
          resolved_at: \
            if alert_revision.alert_resolved_at.present?
              Google::Protobuf::Timestamp.new(seconds: alert_revision.alert_resolved_at.to_i, nanos: alert_revision.alert_resolved_at.nsec)
            end,
          resolution: \
            if alert_revision.alert_resolution.present?
              SecretScanningAlertResolution.lookup(alert_revision.alert_resolution)
            end,
          bypassed: alert_revision.alert_bypassed
        )
        alert_revision.update(alert_bypassed: true)
        assert_equal [:alert_bypassed], alert_revision.fields_with_deviation(alert)
      end

      test "returns alert_validity if it is deviated" do
        alert_revision = create(
          :soa_secret_scanning_alert_revision,
          repository_id: @repo.id,
          alert_number: 1,
          alert_type: "cp_1",
          alert_type_provider: "CP",
          alert_type_slug: "custom_pattern",
          alert_resolved: true,
          alert_resolved_at: Time.now,
          alert_resolution: 2,
          alert_validity: 0
        )
        alert = SecretScanningAlert.new(
          repository_id: alert_revision.repository_id,
          number: alert_revision.alert_number,
          token_type: alert_revision.alert_type,
          token_type_provider: alert_revision.alert_type_provider,
          slug: alert_revision.alert_type_slug,
          resolved: alert_revision.alert_resolved,
          resolved_at: \
            if alert_revision.alert_resolved_at.present?
              Google::Protobuf::Timestamp.new(seconds: alert_revision.alert_resolved_at.to_i, nanos: alert_revision.alert_resolved_at.nsec)
            end,
          resolution: \
            if alert_revision.alert_resolution.present?
              SecretScanningAlertResolution.lookup(alert_revision.alert_resolution)
            end,
          bypassed: alert_revision.alert_bypassed,
          validity: alert_revision.alert_validity
        )
        alert_revision.update(alert_validity: 1)
        assert_equal [:alert_validity], alert_revision.fields_with_deviation(alert)
      end
    end

    context "#update_feature_status_summary" do
      test "enqueues job" do
        model = T.let(create(:soa_secret_scanning_alert_revision), SecretScanningAlertRevision)

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
        model = T.let(create(:soa_secret_scanning_alert_revision), SecretScanningAlertRevision)

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
          model = T.let(create(:soa_secret_scanning_alert_revision, next_revision_date_id: 20240101), SecretScanningAlertRevision)

          UpdateFeatureStatusSummaryJob
            .expects(:enqueue_once_per_interval)
            .never

          model.update_feature_status_summary
        end
      end
    end

    private

    sig { params(kwargs: T.untyped).returns(SecretScanningAlertRevision::UpdatePayload) }
    def update_payload(**kwargs)
      t = Time.now

      update_payload_kwargs = {
        alert_created_at: t, # AnyTime # datetime(3) NOT NULL,
        alert_updated_at: t, # AnyTime # datetime(3) NOT NULL,
        alert_resolved: false, # T::Boolean # tinyint(1) NOT NULL,
        alert_resolved_at: nil, # T.nilable(AnyTime) # datetime(3) DEFAULT NULL,
        alert_resolution: nil, # T.nilable(Integer) # tinyint unsigned DEFAULT NULL,
        alert_type: "cp_1", # String: varchar(64) COLLATE utf8mb4_unicode_520_ci NOT NULL,
        alert_type_provider: "CP", # String: varchar(256) COLLATE utf8mb4_unicode_520_ci NOT NULL,
        alert_type_slug: "custom_pattern", # String: varchar(256) COLLATE utf8mb4_unicode_520_ci NOT NULL,
        alert_bypassed: false, ## T::Boolean # tinyint(1) NOT NULL,
        alert_validity: 0, # Integer # tinyint unsigned DEFAULT '0',
        alert_validity_updated_at: nil, # T.nilable(Integer) # tinyint unsigned DEFAULT NULL,
        **kwargs,
      }

      SecretScanningAlertRevision::UpdatePayload.new(**T.unsafe(update_payload_kwargs))
    end

    sig { params(actual: SecretScanningAlertRevision, payload: SecretScanningAlertRevision::UpdatePayload, repository_id: Integer, alert_number: Integer, next_revision_date_id: Integer).void }
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

      if payload.alert_resolution.nil?
        assert_nil actual.alert_resolution, "alert_resolution"
      else
        refute_nil actual.alert_resolution, "alert_resolution"
        assert_equal payload.alert_resolution, actual.alert_resolution, "alert_resolution"
      end

      if payload.alert_validity_updated_at.nil?
        assert_nil actual.alert_validity_updated_at, "alert_validity_updated_at"
      else
        refute_nil actual.alert_validity_updated_at, "alert_validity_updated_at"
        assert_equal payload.alert_validity_updated_at, actual.alert_validity_updated_at, "alert_validity_updated_at"
      end

      refute_nil actual.alert_validity, "alert_validity"
      assert_equal payload.alert_validity, actual.alert_validity, "alert_validity"

      assert_equal payload.alert_bypassed, actual.alert_bypassed, "alert_bypassed"
      assert_equal payload.alert_resolved, actual.alert_resolved, "alert_resolved"
      assert_equal payload.alert_type, actual.alert_type, "alert_type"
      assert_equal payload.alert_type_provider, actual.alert_type_provider, "alert_type_provider"
      assert_equal payload.alert_type_slug, actual.alert_type_slug, "alert_type_slug"
    end
  end
end
