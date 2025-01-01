# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module BulkActionHelper
    extend T::Helpers

    interface!

    TAlertRevision = T.type_alias do
      T.any(
        T.class_of(CodeScanningAlertRevision),
        T.class_of(DependabotAlertRevision),
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

    module ClassMethods
      extend T::Helpers
      abstract!

      sig do
        params(
          repository_id: Integer,
          alert_number: T.nilable(T.any(Integer, T::Array[Integer])),
          payload: T::Hash[Symbol, T.untyped],
        )
        .returns(Integer)
      end
      def bulk_update(
        repository_id:,
        alert_number:,
        payload:
      )
        T.bind(self, TAlertRevision)

        rows_affected = T.let(0, Integer)
        dogstat_tags = ["feature_type:#{self.feature_type}"]

        rel = self.where(repository_id:)
          .then { |rel| alert_number.present? ? rel.where(alert_number:) : rel }

        rel.in_batches do |batch|
          batch_size = batch.size
          self.throttle_writes_with_retry do
            rows_affected += batch.update_all(**payload)
            GitHub.dogstats.count("security_overview_analytics.bulk_update.count", batch_size, tags: dogstat_tags)
          end
        end

        # recalculate rollup stats after purging a bunch of alert/revision data
        UpdateFeatureStatusSummaryJob.enqueue(repository_id:)

        rows_affected
      end

      sig do
        params(
          repository_id: Integer,
          alert_number: T.nilable(T.any(Integer, T::Array[Integer])),
          alert_id: T.nilable(T.any(Integer, T::Array[Integer])),
        )
        .returns(Integer)
      end
      def bulk_delete(
        repository_id:,
        alert_number: nil,
        alert_id: nil
      )
        T.bind(self, TAlertRevision)

        rows_affected = T.let(0, Integer)
        dogstat_tags = ["feature_type:#{self.feature_type}"]

        rel = self.where(repository_id:)

        # alert_id/alert_number are mutually exclusive for legacy weirdness in code scanning
        if alert_id.present?
          rel = rel.where(alert_id:)
        elsif alert_number.present?
          rel = rel.where(alert_number:)
        end

        rel.in_batches do |batch|
          batch_size = batch.size
          self.throttle_writes_with_retry do
            rows_affected += batch.delete_all
            GitHub.dogstats.count("security_overview_analytics.bulk_delete.count", batch_size, tags: dogstat_tags)
          end
        end

        # recalculate rollup stats after purging a bunch of alert/revision data
        UpdateFeatureStatusSummaryJob.enqueue(repository_id:)

        rows_affected
      end
    end

    mixes_in_class_methods(ClassMethods)
  end
end
