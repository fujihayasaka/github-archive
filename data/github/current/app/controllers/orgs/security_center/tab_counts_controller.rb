# typed: true
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    class TabCountsController < AbstractSecurityCenterController

      # Access
      before_action :organization_read_required
      before_action :security_center_required

      SECRET_SCANNING_GENERIC = "secret_scanning_generic"

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
        add_additional_features_to_data(data)
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

      sig { params(data: T.untyped).void }
      def add_additional_features_to_data(data)
        unless can_view_all_alerts?
          secret_scanning_generic_count_repo_ids = allowed_repository_ids_by_feature_for_organization_members[::SecurityCenter::SecurityFeatures::SECRET_SCANNING]
          repo_ids = secret_scanning_generic_count_repo_ids.first if secret_scanning_generic_count_repo_ids.present?
        end
        if can_view_all_alerts? || repo_ids&.any?
          req = {
            org_selector: {
              owner_id: this_organization.id,
              repository_ids: repo_ids || [],
            },
            low_confidence: true,
          }
          count = GitHub::TokenScanning::Service::Client.new(current_user).get_token_counts(req)&.data&.unresolved_count
          data[SECRET_SCANNING_GENERIC] = count
        end
      rescue GitHub::TokenScanning::Service::Client::Error => e
        log_info("Failed to get secret scanning generic count", "tss.error": e.message)
      end

      memoize def total_open_alert_counts_by_feature_db
        GitHub.dogstats.distribution_time "security_center.total_open_alert_counts_by_feature.dist", tags: datadog_tags do
          ::SecurityOverviewAnalytics::Risk::TabCountsQuery
            .for_organization(
              organization: this_organization,
              repo_ids_by_feature: auth_enumerator.allowed_repository_ids_by_feature,
              user: T.must(current_user),
              user_session: user_session,
              parser: ::Search::Queries::SecurityCenter::RiskQueryParser.new(""),
            )
            .perform
        end
      end

      depends_on_clusters \
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Mysql1,
        ApplicationRecord::SecurityOverviewAnalytics,
        only: [:index]

      depends_on_clusters \
        ApplicationRecord::Copilot,
        ApplicationRecord::Iam,
        ApplicationRecord::Mysql2,
        ApplicationRecord::Mysql5,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Notify,
        ApplicationRecord::Repositories,
        only: [:index],
        optional: true

      instrument_method \
        :index
    end
  end
end
