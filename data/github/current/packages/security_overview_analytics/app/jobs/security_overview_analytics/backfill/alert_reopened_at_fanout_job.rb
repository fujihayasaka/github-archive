# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityOverviewAnalytics
  module Backfill
    class AlertReopenedAtFanoutJob < FanoutBaseJob
      include GitHub::Memoizer

      FEATURES = T.let(%w[code_scanning secret_scanning dependabot], T::Array[String])

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

      queue_as :security_overview_analytics_on_demand_backfill

      around_perform do |_job, block|
        if FeatureFlag.vexi.enabled?(:security_center_backfill_alert_reopened_at, default: false)
          block.call
        end
      end

      sig do
        override.params(
          owner_repo_ids: T::Array[[Integer, Integer]],
          args: T.untyped,
          features: T.nilable(T::Array[String]),
          dry_run: T::Boolean,
          kwargs: T.untyped
        ).void
      end
      def process_batch(owner_repo_ids, *args, features: nil, dry_run: false, **kwargs)
        features_to_backfill = features.nil? ? FEATURES : features & FEATURES
        return if features_to_backfill.empty?

        repo_to_owner_lookup = owner_repo_ids.to_h { |owner_id, repo_id| [repo_id, owner_id] }

        log_timing(step: "process_batch") do
          features_to_backfill.each do |feature|
            # Make sure we're only queueing jobs for repos with alerts
            model = T.must(feature_model(feature))
            model
              .where(repository_id: owner_repo_ids.map(&:second))
              .distinct # because of the pluck, this will be distinct repository_ids
              .pluck(:repository_id)
              .each do |repo_id|
                AlertReopenedAtJob.perform_later(
                  feature:,
                  repository_id: repo_id,
                  owner_id: repo_to_owner_lookup[repo_id],
                  dry_run:
                )
              end
          end
        end
      end

      sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
      def fanout_jobs
        [AlertReopenedAtJob]
      end

      private

      sig { params(feature: String).returns(T.nilable(TAlertRevision)) }
      def feature_model(feature)
        case feature
        when "code_scanning"
          CodeScanningAlertRevision
        when "secret_scanning"
          SecretScanningAlertRevision
        when "dependabot"
          DependabotAlertRevision
        else
          nil
        end
      end
    end
  end
end
