# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class FeatureStatusRevision < ApplicationRecord::SecurityOverviewAnalytics
    include RevisionCompressor

    self.table_name = "soa_feature_status_revisions"

    after_commit :update_feature_status_summary
    after_commit :synchronize_search_index, if: :write_to_elasticsearch?

    sig { void }
    def update_feature_status_summary
      return unless next_revision_date_id == Date::FUTURE_DATE_ID
      UpdateFeatureStatusSummaryJob.enqueue(repository_id:)
    end

    sig { void }
    def synchronize_search_index
      reason = reason_to_be_unsearchable
      es_adapter_type = T.must(Elastomer::Adapters::RepositorySecurityAlertMetadata.name).demodulize.underscore
      tags = ["adapter:#{es_adapter_type}"]

      if reason
        GitHub.logger.info(
          "Removing from search index",
          "code.namespace": self.class.name,
          "code.function": __method__.to_s,
          "gh.repo.id": repository_id,
          "gh.security_overview_analytics.feature_status_revision.id": id,
          "gh.security_alerts.search_index_removal_reason": reason,
        )

        GitHub.dogstats.increment("security_overview_analytics.synchronize_search_index.remove", tags: tags + ["reason:#{reason}"])
        RemoveFromSearchIndexJob.perform_later(es_adapter_type, id)
      else
        GitHub.logger.info(
          "Adding to search index",
          "code.namespace": self.class.name,
          "code.function": __method__.to_s,
          "gh.repo.id": repository_id,
          "gh.security_overview_analytics.feature_status_revision.id": id,
        )

        GitHub.dogstats.increment("security_overview_analytics.synchronize_search_index.add", tags:)
        Search.add_to_search_index(es_adapter_type, id)
      end
    end

    belongs_to :date,
      class_name: SecurityOverviewAnalytics::Date.name,
      inverse_of: :feature_status_revisions
    belongs_to :next_revision_date,
      class_name: SecurityOverviewAnalytics::Date.name,
      inverse_of: :last_feature_status_revisions
    belongs_to :repository_metadata,
      class_name: SecurityOverviewAnalytics::Repository.name,
      foreign_key: :repository_id,
      inverse_of: :feature_status_revisions
    belongs_to :repository, class_name: "::Repository"

    class UpdatePayload < T::Struct
      include GitHub::Memoizer

      const :dependabot_alerts_enabled, T.nilable(T::Boolean)
      const :dependabot_security_updates_enabled, T.nilable(T::Boolean)
      const :advanced_security_enabled, T.nilable(T::Boolean)
      const :code_scanning_enabled, T.nilable(T::Boolean)
      const :code_scanning_pr_alerts_enabled, T.nilable(T::Boolean)
      const :code_scanning_auto_codeql_enabled, T.nilable(T::Boolean)
      const :code_scanning_auto_codeql_eligible, T.nilable(T::Boolean)
      const :secret_scanning_enabled, T.nilable(T::Boolean)
      const :secret_scanning_push_protection_enabled, T.nilable(T::Boolean)

      sig { returns(T::Hash[String, T::Boolean]) }
      memoize def serialize
        # This is method does not alter the behavior of serialize.
        # It is only to explicitly declare the typing of the return value.
        super
      end
    end

    class << self

      private

      sig do
        params(
          repository_id: Integer,
          date_id: Integer,
          next_revision_date_id: Integer,
          previous_revision: T.nilable(FeatureStatusRevision),
          payload: T::Hash[Symbol, T::Boolean]
        ).void
      end
      def insert_new_revision(repository_id:, date_id:, next_revision_date_id:, previous_revision:, payload:)
        self.create!({
          date_id:,
          next_revision_date_id:,
          repository_id:,
          dependabot_alerts_enabled: previous_revision&.dependabot_alerts_enabled || 0,
          dependabot_security_updates_enabled: previous_revision&.dependabot_security_updates_enabled || 0,
          advanced_security_enabled: previous_revision&.advanced_security_enabled || 0,
          secret_scanning_enabled: previous_revision&.secret_scanning_enabled || 0,
          secret_scanning_push_protection_enabled: previous_revision&.secret_scanning_push_protection_enabled || 0,
          code_scanning_enabled: previous_revision&.code_scanning_enabled || 0,
          code_scanning_pr_alerts_enabled: previous_revision&.code_scanning_pr_alerts_enabled || 0,
          code_scanning_auto_codeql_enabled: previous_revision&.code_scanning_auto_codeql_enabled || 0,
          code_scanning_auto_codeql_eligible: previous_revision&.code_scanning_auto_codeql_eligible || 0,
        }.merge(payload))
      end

      sig do
        params(
          repository_id: Integer,
          date_id: Integer,
          latest_revision: T.nilable(FeatureStatusRevision),
          event_payload: T::Hash[String, T::untyped],
          upsert_scenario: T.nilable(String)
        ).void
      end
      def report_duplicate_revisions(repository_id:, date_id:, latest_revision:, event_payload:, upsert_scenario:)
        GitHub.logger.info(
          "#{self.name} Duplicate revisions detected",
          "code.namespace": self.name,
          "code.function": __method__,
          "gh.repo.id": repository_id,
          "gh.security_overview_analytics.feature_type": "feature_status",
          "gh.security_overview_analytics.new_revision.date": date_id,
          "gh.security_overview_analytics.new_revision.payload": event_payload,
          "gh.security_overview_analytics.last_revision.date_id": latest_revision&.date_id,
          "gh.security_overview_analytics.last_revision.created_at": latest_revision&.created_at,
          "gh.security_overview_analytics.last_revision.updated_at": latest_revision&.updated_at,
          "gh.security_overview_analytics.upsert_scenario": upsert_scenario,
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.revision_upserter.duplicate_revisions.detected",
          tags: ["feature_type:feature_status"],
        )
      end

      sig { params(repository_id: Integer).returns(::Repository) }
      def get_repository(repository_id)
        ::Repositories::Public.get_active_or_deleted!(repository_id)
      end
    end

    sig { returns(T::Array[Symbol]) }
    def find_deviations
      return [:repo_not_found] if repository.nil?
      return [:repo_deleted] if repository&.deleted?

      output = T.let([], T::Array[Symbol])

      output << :dependabot_alerts_enabled if dependabot_alerts_enabled != repository&.security_feature_configured?(:DEPENDABOT_ALERTS)
      output << :dependabot_security_updates_enabled if dependabot_security_updates_enabled != repository&.security_feature_configured?(:DEPENDABOT_SECURITY_UPDATES)
      output << :advanced_security_enabled if advanced_security_enabled != repository&.security_feature_configured?(:ADVANCED_SECURITY)
      output << :code_scanning_enabled if code_scanning_enabled != repository&.security_feature_configured?(:CODE_SCANNING)
      output << :code_scanning_pr_alerts_enabled if code_scanning_pr_alerts_enabled != repository&.security_feature_configured?(:CODE_SCANNING_PR_REVIEWS)
      output << :secret_scanning_enabled if secret_scanning_enabled != repository&.security_feature_configured?(:SECRET_SCANNING)
      output << :secret_scanning_push_protection_enabled if secret_scanning_push_protection_enabled != repository&.security_feature_configured?(:SECRET_SCANNING_PUSH_PROTECTION)

      self.class.code_scanning_auto_codeql_status(repository:)&.tap do |auto_codeql_status|
        auto_codeql_status => { enabled:, eligible: }
        output << :code_scanning_auto_codeql_enabled if code_scanning_auto_codeql_enabled != enabled
        output << :code_scanning_auto_codeql_eligible if code_scanning_auto_codeql_eligible != eligible
      end

      output
    end

    sig { params(repository: T.nilable(::Repository)).returns(T.nilable({ enabled: T::Boolean, eligible: T::Boolean })) }
    def self.code_scanning_auto_codeql_status(repository:)
      return unless repository.present?

      case repository.code_scanning_auto_codeql_security_center_status(repository.actor).scanning_status
      when "enrolled"
        { enabled: true, eligible: true }
      when "eligible"
        { enabled: false, eligible: true }
      else
        { enabled: false, eligible: false }
      end
    end

    sig { returns(String) }
    def self.feature_type
      "feature_status"
    end

    sig do
      params(
        repository_id: Integer,
        date_id: Integer,
        payload: UpdatePayload
      ).void
    end
    def self.upsert_feature_status(repository_id:, date_id:, payload:)
      retry_count ||= 0

      latest_revision = T.let(nil, T.nilable(FeatureStatusRevision))
      serialized_payload = payload.serialize.symbolize_keys
      # Create a copy of the payload to compare with the previous revision
      required_fields = serialized_payload.keys
      event_payload = serialized_payload.transform_values { |v| v.is_a?(Symbol) ? v.to_s : v }
      repo = get_repository(repository_id)
      found_duplicate_revisions = T.let(false, T::Boolean)

      dog_stats = T.let([*serialized_payload.keys.map { |k| "feature:#{k}" }], T::Array[String])
      if date_id < Date.id_from_time(1.day.ago)
        GitHub.logger.info(
          "Feature status change skipped.",
          "code.namespace": self.name,
          "code.function": __method__,
          "gh.security_overview_analytics.reason": "date_id is older than 1 day ago.",
          "gh.security_overview_analytics.payload": serialized_payload,
          "gh.security_overview_analytics.revision.date": date_id,
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.upsert_feature_status.skipped",
          tags: dog_stats + ["reason:old_date_id"]
        )
        return
      end

      next_revision_date_id = T.let(Date::FUTURE_DATE_ID, Integer)
      upsert_scenario = T.let(nil, T.nilable(String))

      self.transaction do
        latest_revision = self.where(repository_id:, next_revision_date_id:).order(date_id: :desc).first&.lock!

        if latest_revision.nil?
          insert_new_revision(repository_id:, date_id:, next_revision_date_id:, previous_revision: nil, payload: serialized_payload)
          upsert_scenario = "insert_initial_revision"
          next
        end

        # Check for duplicate revisions
        latest_revision_hash = latest_revision.attributes.symbolize_keys.select { |k| required_fields.include?(k) }
        if event_payload == latest_revision_hash
          # If there's no difference between the payload and previous revision, that means we've encountered a duplicate
          found_duplicate_revisions = true
        end

        if latest_revision.date_id == date_id
          latest_revision.update!(serialized_payload)
          upsert_scenario = "update_latest_revision"
          next
        end

        if latest_revision.date_id < date_id
          next_revision_date_id = latest_revision.next_revision_date_id if latest_revision.next_revision_date_id > date_id
          previous_revision = if latest_revision.next_revision_date_id <= date_id
            upsert_scenario = "insert_from_unexpected_previous_revision"
            T.let(self.find_by(repository_id:, date_id: latest_revision.next_revision_date_id)&.lock! || latest_revision, T.nilable(FeatureStatusRevision))
          else
            upsert_scenario = "insert_from_latest_revision"
            T.let(latest_revision, T.nilable(FeatureStatusRevision))
          end
          previous_revision.update!(next_revision_date_id: date_id) if previous_revision.present? && previous_revision.date_id < date_id
          insert_new_revision(repository_id:, date_id:, next_revision_date_id:, previous_revision:, payload: serialized_payload)
          next
        end

        if latest_revision.date_id > date_id
          next_revision_date_id = latest_revision.date_id
          previous_revision = T.let(self.where(repository_id:).where("date_id <= ?", date_id).order(date_id: :desc).first&.lock!, T.nilable(FeatureStatusRevision))
          if previous_revision.present? && previous_revision.date_id == date_id
            previous_revision.update!(serialized_payload)
            upsert_scenario = "update_previous_revision"
          else
            previous_revision.update!(next_revision_date_id: date_id) if previous_revision.present?
            insert_new_revision(repository_id:, date_id:, next_revision_date_id:, previous_revision:, payload: serialized_payload)
            upsert_scenario = "insert_as_previous_revision"
          end
          next
        end
      end

      GitHub.logger.info(
        "Feature status change processed.",
        "code.namespace": self.name,
        "code.function": __method__,
        "gh.security_overview_analytics.upsert_scenario": upsert_scenario,
        "gh.security_overview_analytics.payload": serialized_payload,
        "gh.security_overview_analytics.revision.date": date_id,
      )
      GitHub.dogstats.increment(
        "security_overview_analytics.upsert_feature_status.succeeded",
        tags: dog_stats + ["upsert_scenario:#{upsert_scenario}"]
      )
    rescue ActiveRecord::RecordNotUnique => e
      raise e unless retry_count&.zero?

      GitHub.logger.info(
        "Failed to insert revision. Retrying to update instead.",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.repo.id": repository_id,
        "gh.security_overview_analytics.upsert_scenario": upsert_scenario,
        "gh.security_overview_analytics.payload": serialized_payload,
        "gh.security_overview_analytics.revision.date": date_id,
      )
      GitHub.dogstats.increment(
        "security_overview_analytics.upsert_feature_status.retried",
        tags: (dog_stats || []) + ["upsert_scenario:#{upsert_scenario}"]
      )
      retry_count += 1
      retry
    rescue ActiveRecord::Deadlocked => e
      # Always report a deadlock error to Failbot since jobs can intercept and retry on it.
      Failbot.report e
      raise e
    ensure
      report_duplicate_revisions(repository_id:, date_id:, latest_revision:, event_payload:, upsert_scenario:) if found_duplicate_revisions
    end

    sig do
      override.params(
        repository_id: Integer,
        alert_number: T.nilable(Integer), # not applicable, but we need to include this param as part of the override
        dry_run: T::Boolean
      ).void
    end
    def self.compress_revisions(repository_id:, alert_number: nil, dry_run: false)
      deleted_revisions = []
      revisions = self.where(repository_id:).order(date_id: :asc)
      current_rev = T.let(revisions.first, T.nilable(FeatureStatusRevision))

      unless current_rev.nil?
        next_rev = T.let(
          revisions
            .where(date_id: current_rev.next_revision_date_id)
            .where("next_revision_date_id < ?", Date::FUTURE_DATE_ID)
            .first,
          T.nilable(FeatureStatusRevision)
        )

        # If there there is no next revision, or the next revision is the last in the chain, return
        while next_rev
          # Check if the next revision was updated in the last two weeks to cover potential out-of-event cases
          if next_rev.date_id > (::Date.current - 14).strftime("%Y%m%d").to_i
            GitHub.logger.info(
              "Skipped revision due to being updated in the last two weeks",
              "gh.repo.id": repository_id,
              "gh.security_overview_analytics.feature_type": self.feature_type,
              "gh.security_overview_analytics.date_id": next_rev.date_id,
            )
            GitHub.dogstats.increment(
              "security_overview_analytics.duplicate_revisions.skipped",
              tags: ["feature_type:#{self.feature_type}"],
            )

            next_rev = nil
            next
          end

          required_fields = self.fields_to_serialize
          current_rev_hash = current_rev.attributes.symbolize_keys.select { |k| required_fields.include?(k) }
          next_rev_hash = next_rev.attributes.symbolize_keys.select { |k| required_fields.include?(k) }

          if current_rev_hash == next_rev_hash
            deleted_rev = {
              next_revision_date_id: next_rev.next_revision_date_id,
              date_id: next_rev.date_id,
              updated_at: next_rev.updated_at,
            }

            unless dry_run
              self.transaction do
                self.throttle_writes_with_retry do
                  # We have to destroy the next revision before updating the current revision to avoid unique constraint errors
                  next_rev.destroy!
                  current_rev.update!(next_revision_date_id: deleted_rev[:next_revision_date_id])
                end
              end
            end

            deleted_revisions << deleted_rev
            next_rev = revisions
              .where(date_id: deleted_rev[:next_revision_date_id])
              .where("next_revision_date_id < ?", Date::FUTURE_DATE_ID)
              .first
          else
            ## Only update the current revision if the next revision is not a duplicate
            current_rev = next_rev
            next_rev = revisions
              .where(date_id: current_rev.next_revision_date_id)
              .where("next_revision_date_id < ?", Date::FUTURE_DATE_ID)
              .first
          end
        end
      end

      if deleted_revisions.any?
        GitHub.logger.info(
          "#{dry_run ? "Will remove" : "Removed"} #{deleted_revisions.count} duplicate revisions",
          "gh.repo.id": repository_id,
          "gh.security_overview_analytics.feature_type": self.feature_type,
          "gh.security_overview_analytics.deleted_revisions": deleted_revisions,
        )

        unless dry_run
          GitHub.dogstats.count(
            "security_overview_analytics.duplicate_revisions.removed",
            deleted_revisions.count,
            tags: ["feature_type:#{self.feature_type}"],
          )
        end
      end
    end

    sig { override.returns(T::Array[Symbol]) }
    def self.fields_to_serialize
      UpdatePayload.props.keys
    end

    sig do
      params(repository_id: Integer).void
    end
    def self.delete_repository_revisions(repository_id:)
      delete_by_repository_ids([repository_id])
    end

    sig { params(repository_ids: T::Array[Integer]).void }
    def self.delete_by_repository_ids(repository_ids)
      self.where(repository_id: repository_ids).in_batches do |batch|
        batch_size = batch.size
        self.throttle_writes_with_retry do
          batch.delete_all
          GitHub.dogstats.count("security_overview_analytics.feature_status_revisions.deleted", batch_size)
        end
      end
    end

    sig { returns(T::Boolean) }
    def write_to_elasticsearch?
      FeatureFlagHelper.write_to_elasticsearch?(repository, repository&.owner)
    end

    # Returns a symbol representing why this alert should not appear in search
    # results. If this method returns nil, the alert *should* be searchable.
    batch_method(:reason_to_be_unsearchable, T.nilable(Symbol)) do |revisions|
      GitHub::PrefillAssociations.prefill_associations(revisions, [:repository_metadata])

      revisions.index_with do |revision|
        case
        when !revision.write_to_elasticsearch? then :feature_disabled
        when revision.next_revision_date_id != Date::FUTURE_DATE_ID then :old_feature_status
        when revision.repository_metadata.nil? then :repository_metadata_missing
        end
      end
    end

    # Returns a Base64 encoded string representing the current revision data as it
    # should appear in the search index. If this signature generated on the model
    # doesn't match the signature stored in the search index, the alert should be
    # reindexed in Elasticsearch.
    #
    # This method returns nil if the alert is not searchable.
    batch_method(:search_index_signature, T.nilable(String)) do |revisions|
      Elastomer::Adapters::RepositorySecurityAlertMetadata.prefill_payload(revisions)
      revisions.index_with { |revision| Elastomer::Adapters::RepositorySecurityAlertMetadata.generate_signature(revision) }
    end

    # Returns whether this alert should be findable in search results. There are
    # many reasons an alert might not be searchable. See the
    # reason_to_be_unsearchable method for more details.
    batch_method(:searchable?, T::Boolean) do |revisions|
      GitHub::PrefillAssociations.prefill_batch_method(revisions, :reason_to_be_unsearchable)
      revisions.index_with { |alert| alert.reason_to_be_unsearchable.nil? }
    end
  end
end
