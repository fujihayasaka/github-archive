# typed: true
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    class TabCountsController < AbstractSecurityCenterController
      extend T::Sig

      # Access
      before_action :organization_read_required
      before_action :security_center_required

      sig { void }
      def index
        data = log_timing(step: "build payload") do
          tab_count_data
        end

        log_timing(step: "render") do
          render_camelback_json(json: { data: })
        end
      end

      private

      sig { returns(T::Hash[String, Integer]) }
      def tab_count_data
        counts_by_feature = total_open_alert_counts_by_feature

        counts_by_feature.reduce({}) do |memo, (k, v)|
          memo[k.to_s] = { openCount: v }
          memo
        end
      rescue ActiveRecord::ActiveRecordError
        # Graceful fallback in case of database error
        # Returning an empty object means we won't show any counts
        {}
      end

      def total_open_alert_counts_by_feature
        kv_key = "security_center.total_open_alert_counts_by_feature.#{this_organization.id}.#{current_user.id}"

        kv_value = ::SecurityCenter::KV.store.get(kv_key).value { nil }
        unless kv_value.nil?
          GitHub.dogstats.increment("security_center.total_open_alert_counts_by_feature.count", tags: datadog_tags + ["cache:hit"])
          log_info("Open alert counts cache hit")
          return JSON.load(kv_value)
        end

        data = total_open_alert_counts_by_feature_db
        ActiveRecord::Base.connected_to(role: :writing) do
          ::SecurityCenter::KV.store.set(kv_key, JSON.dump(data), expires: 10.minutes.from_now)
        end

        GitHub.dogstats.increment("security_center.total_open_alert_counts_by_feature.count", tags: datadog_tags + ["cache:miss"])
        log_info("Open alert counts cache miss")

        data
      rescue => exception # rubocop:disable Lint/GenericRescue
        # Reports exception but does not block the page if fails to attempt the backfill
        Failbot.report exception
        total_open_alert_counts_by_feature_db
      end

      memoize def total_open_alert_counts_by_feature_db
        GitHub.dogstats.distribution_time "security_center.total_open_alert_counts_by_feature.dist", tags: datadog_tags do
          allowed_repo_ids_by_feature = visible_features.reduce({}) do |memo, feature_type|
            if can_manage_security_products?
              memo[feature_type] = nil # repo ids scope is not available for admins/security managers
              memo
            else
              repo_ids, _ = allowed_repository_ids_by_feature_for_organization_members[feature_type]
              return memo if repo_ids.nil? # Shouldn't be possible but skip instead of leaking repos
              memo[feature_type] = repo_ids
              memo
            end
          end

          return {} if allowed_repo_ids_by_feature.blank?

          rel = allowed_repo_ids_by_feature.reduce(nil) do |rel, (feature_type, repo_ids)|
            base_query = if feature_type == ::SecurityCenter::SecurityFeatures::SECRET_SCANNING
              this_organization.security_center_repo_config_status_scope
            else
              this_organization.security_center_repo_config_status_scope.where(archived: false)
            end

            rel_by_feature = base_query
              .where(repository_security_center_statuses: { feature_type: feature_type })
              .where("repository_security_center_statuses.scanning_count > 0")
              .where.not(repository_security_center_statuses: { scanning_status: :not_enrolled })

            # Scope to allowed repos if exists. It is nil for org admin/security managers
            rel_by_feature = rel_by_feature.where(repository_id: repo_ids) unless repo_ids.nil?

            rel.nil? ? rel_by_feature : rel.or(rel_by_feature)
          end
          count_by_feature = rel.group(:feature_type).sum(:scanning_count)

          # Normalize count value. If feature count doesn't exist but its visible, default to 0
          visible_features.reduce({}) do |memo, feature_type|
            memo[feature_type] = count_by_feature[feature_type]&.round || 0
            memo
          end
        end
      end

      depends_on_clusters \
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Mysql1,
        only: [:index]

      depends_on_clusters \
        ApplicationRecord::Copilot,
        ApplicationRecord::Iam,
        ApplicationRecord::Mysql2,
        ApplicationRecord::Mysql5,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Notify,
        ApplicationRecord::Repositories,
        ApplicationRecord::SecurityOverviewAnalytics,
        only: [:index],
        optional: true

      instrument_method \
        :index
    end
  end
end
