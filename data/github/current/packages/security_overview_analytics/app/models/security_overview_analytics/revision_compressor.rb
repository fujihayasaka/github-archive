# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module RevisionCompressor
    extend T::Sig
    extend T::Helpers

    interface!

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
        T.class_of(FeatureStatusRevision),
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
      extend T::Sig
      extend T::Helpers
      abstract!

      sig { abstract.returns(T::Array[Symbol]) }
      def fields_to_serialize; end

      sig do
        overridable.params(
          repository_id: Integer,
          alert_number: Integer,
          dry_run: T::Boolean,
        ).void
      end
      def compress_revisions(repository_id:, alert_number:, dry_run: false)
        T.bind(self, TAlertRevision)

        deleted_revisions = []
        revisions = self
          .where(repository_id:, alert_number:)
          .order(date_id: :asc)
        current_rev = T.let(revisions.first, T.nilable(IAlertRevision))

        unless current_rev.nil?
          next_rev = T.let(
            revisions
              .where(date_id: current_rev.next_revision_date_id)
              .where("next_revision_date_id < ?", Date::FUTURE_DATE_ID)
              .first,
            T.nilable(IAlertRevision)
          )

          # If there there is no next revision, or the next revision is the last in the chain, return
          while next_rev
            # Check if the next revision was updated in the last two weeks to cover potential out-of-event cases
            if next_rev.date_id > (::Date.current - 14).strftime("%Y%m%d").to_i
              GitHub.logger.info(
                "Skipped revision due to being updated in the last two weeks",
                "gh.repo.id": repository_id,
                "gh.security_overview_analytics.feature_type": self.feature_type,
                "gh.security_overview_analytics.alert.number": alert_number,
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
                alert_updated_at: next_rev.alert_updated_at,
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
              # Only update the current revision if the next revision is not a duplicate
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
            "gh.security_overview_analytics.alert.number": alert_number,
            "gh.security_overview_analytics.deleted_revisions": deleted_revisions,
          )

          GitHub.dogstats.count(
            "security_overview_analytics.duplicate_revisions.removed",
            deleted_revisions.count,
            tags: ["feature_type:#{self.feature_type}"],
          )
        end
      end
    end

    mixes_in_class_methods(ClassMethods)
  end
end
