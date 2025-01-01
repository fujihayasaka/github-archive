# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class RevisionUpserter
    extend T::Sig

    IAlertRevision = T.type_alias do
      T.any(
        DependabotAlertRevision,
        CodeScanningAlertRevision,
        SecretScanningAlertRevision,
      )
    end

    TAlertRevision = T.type_alias do
      T.any(
        T.class_of(DependabotAlertRevision),
        T.class_of(CodeScanningAlertRevision),
        T.class_of(SecretScanningAlertRevision),
      )
    end

    IAlertRevisionPayload = T.type_alias do
      T.any(
        DependabotAlertRevision::UpdatePayload,
        CodeScanningAlertRevision::UpdatePayload,
        SecretScanningAlertRevision::UpdatePayload,
      )
    end

    sig { returns(TAlertRevision) }
    attr_reader :model

    sig { returns(String) }
    attr_reader :feature_type

    sig { params(model: TAlertRevision).void }
    def initialize(model)
      @model = model
      @feature_type = T.let(model.feature_type, String)
    end

    sig do
      params(
        payload: IAlertRevisionPayload,
        repository_id: Integer,
        alert_number: Integer,
        date_id: Integer,
        force_rewrite: T::Boolean,
        alert_id: T.nilable(Integer)
      ).void
    end
    def upsert(payload, repository_id:, alert_number:, date_id:, force_rewrite: false, alert_id: nil)
      retry_count ||= 0

      upsert_scenario = T.let("noop", String)
      prev_revision = T.let(nil, T.nilable(IAlertRevision))
      found_broken_chain = T.let(false, T::Boolean)

      # Drop microseconds due to difference in precision in how timestamps are stored across systems.
      serialized_payload = payload.serialize
      serialized_payload["alert_resolved_at"] = serialized_payload["alert_resolved_at"]&.iso8601(3)&.to_time&.utc
      serialized_payload["alert_created_at"] = serialized_payload["alert_created_at"]&.iso8601(3)&.to_time&.utc
      serialized_payload["alert_updated_at"] = serialized_payload["alert_updated_at"]&.iso8601(3)&.to_time&.utc

      # Create a copy of the payload to compare with the previous revision
      repo = ::Repositories::Public.find_active(repository_id)
      report_duplicate_revisions = FeatureFlagHelper.report_duplicate_revisions?(repo)
      required_fields = serialized_payload.keys
      event_payload = serialized_payload.transform_values { |v| v.is_a?(Symbol) ? v.to_s : v }
      found_duplicate_revisions = T.let(false, T::Boolean)

      # TODO - remove this temporary logic once alert_number has been backfilled - https://github.com/github/security-center/issues/5175
      base_rel = if alert_id.present?
        model.where(repository_id:, alert_id:)
      else
        model.where(repository_id:, alert_number:)
      end

      model.transaction do
        loop do
          # Because of exclusive locking, we can be sure that we're operating on the latest committed state of a specific revision.
          # But while waiting for the lock to release, the transaction that previously held the lock could have inserted
          # a newer 'prev_revision'. In that case, we keep asking for the previous revision until we get a lock on
          # one that has a `next_revision_date_id` greater than the date_id we're trying to insert/update.
          last_loop_revision_id = prev_revision&.id
          # prev_revision = find_revision
          prev_revision = T.let(
            base_rel
              .where("date_id <= ?", date_id)
              .order(date_id: :desc)
              .first&.lock!,
            T.nilable(IAlertRevision),
          )

          break if prev_revision.nil? # No revision before this one.
          break if prev_revision.next_revision_date_id > date_id # Found the previous revision we need to update.

          # Stop if we find the same revision twice.
          # This means the previous revision is pointing to itself, a revision before itself, or a revision before date_id that doesn't exist.
          if last_loop_revision_id == prev_revision.id
            found_broken_chain = true
            break
          end
        end

        serialized_payload["alert_reopened_at"] = if prev_revision
          if prev_revision.alert_resolved? && !serialized_payload["alert_resolved"]
            # If the previous revision was resolved and this revision is not resolved, we need to update the reopened
            # at timestamp.
            serialized_payload["alert_updated_at"]
          elsif prev_revision.alert_reopened_at?
            # In all other cases, we need to keep the reopened at timestamp from the previous revision if it exists.
            prev_revision.alert_reopened_at
          end
        end

        if prev_revision && report_duplicate_revisions
          prev_revision_hash = prev_revision.attributes.select { |k| required_fields.include?(k) }
          if event_payload == prev_revision_hash
            # If there's no difference between the payload and previous revision, that means we've encountered a duplicate
            found_duplicate_revisions = true
          end
        end

        if prev_revision && prev_revision.date_id == date_id
          # Drop microseconds for comparison.
          prev_revision_updated_at = prev_revision.alert_updated_at.iso8601(3).to_time.utc
          force_update = force_rewrite && prev_revision_updated_at == serialized_payload["alert_updated_at"]
          if force_update || prev_revision_updated_at < serialized_payload["alert_updated_at"]
            prev_revision.update!(serialized_payload)
            upsert_scenario = "update"
          end
        else
          next_revision_date_id =
            if prev_revision.nil? || found_broken_chain
              # When there's no previous revision or it is not pointing at a future one properly (broken chain),
              # we need to decide the correct `next_revision_date_id` based on the future revision.
              n_id = base_rel
                .where("date_id > ?", date_id)
                .order(date_id: :asc)
                .pick(:date_id)
              n_id || Date::FUTURE_DATE_ID
            elsif prev_revision.next_revision_date_id > date_id
              prev_revision.next_revision_date_id
            else
              Date::FUTURE_DATE_ID
            end

          if next_revision_date_id < Date.min_next_date_id
            # A newer revision exists outside of retention limit, so we skip this change.
            upsert_scenario = "upsert_skipped_for_retention_limit"
            next
          end

          upsert_scenario = "insert_revision"

          unless prev_revision.nil? || prev_revision.next_revision_date_id == date_id
            prev_revision.update!(next_revision_date_id: date_id)
            upsert_scenario = "insert_revision_and_update_prev_revision"
          end

          model.create!({
            repository_id:,
            alert_number:,
            date_id:,
            next_revision_date_id:,
            **serialized_payload,
          })
        end
      end

      GitHub.logger.info(
        "#{self.class.name} upsert processed.",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.repo.id": repository_id,
        "gh.security_overview_analytics.force_rewrite": force_rewrite,
        "gh.security_overview_analytics.payload": serialized_payload,
        "gh.security_overview_analytics.feature_type": feature_type,
        "gh.security_overview_analytics.revision.alert_number": alert_number,
        "gh.security_overview_analytics.revision.alert_id": alert_id,
        "gh.security_overview_analytics.revision.date": date_id,
        "gh.security_overview_analytics.upsert_scenario": upsert_scenario,
      )
      GitHub.dogstats.increment(
        "security_overview_analytics.revision.upsert.succeeded",
        tags: [
          "feature_type:#{feature_type}",
          "upsert_scenario:#{upsert_scenario}",
          "force_rewrite:#{force_rewrite}",
        ],
      )

    rescue ActiveRecord::RecordNotUnique => e
      # If we failed to insert a record because another transaction beat us to it for the same repo-number-date combo,
      # a retry should go down the update path instead.
      if retry_count&.zero?
        GitHub.logger.info(
          "Failed to insert revision. Retrying to update instead.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.repo.id": repository_id,
          "gh.security_overview_analytics.force_rewrite": force_rewrite,
          "gh.security_overview_analytics.feature_type": feature_type,
          "gh.security_overview_analytics.revision.alert_number": alert_number,
          "gh.security_overview_analytics.revision.alert_id": alert_id,
          "gh.security_overview_analytics.revision.date": date_id,
        )

        retry_count += 1
        retry
      end

      raise e
    ensure
      report_broken_revision_chain(repository_id:, alert_number:, alert_id:, date_id:, found_last_revision: prev_revision) if found_broken_chain
      report_duplicate_revisions(repository_id:, alert_number:, alert_id:, date_id:, prev_revision:, event_payload:, upsert_scenario:) if found_duplicate_revisions
    end

    sig do
      params(
        repository_id: Integer,
        alert_number: Integer,
        alert_id: T.nilable(Integer),
        date_id: Integer,
        found_last_revision: T.nilable(IAlertRevision)
      ).void
    end
    def report_broken_revision_chain(repository_id:, alert_number:, alert_id:, date_id:, found_last_revision:)
      GitHub.logger.warn(
        "Found broken alert revision chain.",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.repo.id": repository_id,
        "gh.security_overview_analytics.feature_type": feature_type,
        "gh.security_overview_analytics.revision.alert_number": alert_number,
        "gh.security_overview_analytics.revision.alert_id": alert_id,
        "gh.security_overview_analytics.revision.date_id": date_id,
        "gh.security_overview_analytics.last_revision.date_id": found_last_revision&.date_id,
        "gh.security_overview_analytics.last_revision.next_revision_date_id": found_last_revision&.next_revision_date_id,
      )
      GitHub.dogstats.increment(
        "security_overview_analytics.revision_upserter.broken_revision_chain.detected",
        tags: ["feature_type:#{feature_type}"],
      )
    end

    sig do
      params(
        repository_id: Integer,
        alert_number: Integer,
        alert_id: T.nilable(Integer),
        date_id: Integer,
        prev_revision: T.nilable(IAlertRevision),
        event_payload: T::Hash[String, T::untyped],
        upsert_scenario: String
      ).void
    end
    def report_duplicate_revisions(repository_id:, alert_number:, alert_id:, date_id:, prev_revision:, event_payload:, upsert_scenario:)
      GitHub.logger.info(
        "#{self.class.name} Duplicate revisions detected",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.repo.id": repository_id,
        "gh.security_overview_analytics.feature_type": feature_type,
        "gh.security_overview_analytics.new_revision.alert_number": alert_number,
        "gh.security_overview_analytics.new_revision.alert_id": alert_id,
        "gh.security_overview_analytics.new_revision.date": date_id,
        "gh.security_overview_analytics.new_revision.alert_updated_at": event_payload["alert_updated_at"],
        "gh.security_overview_analytics.new_revision.payload": event_payload,
        "gh.security_overview_analytics.last_revision.date_id": prev_revision&.date_id,
        "gh.security_overview_analytics.last_revision.alert_updated_at": prev_revision&.alert_updated_at,
        "gh.security_overview_analytics.last_revision.created_at": prev_revision&.created_at,
        "gh.security_overview_analytics.last_revision.updated_at": prev_revision&.updated_at,
        "gh.security_overview_analytics.upsert_scenario": upsert_scenario,

      )
      GitHub.dogstats.increment(
        "security_overview_analytics.revision_upserter.duplicate_revisions.detected",
        tags: ["feature_type:#{feature_type}"],
      )
    end
  end
end
