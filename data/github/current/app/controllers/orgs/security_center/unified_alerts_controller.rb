# typed: strict
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    class UnifiedAlertsController < AbstractSecurityCenterController
      extend T::Sig
      include ReactHelper
      include ApplicationHelper

      UnifiedAlerts = ::SecurityCenter::UnifiedAlerts
      SecurityFeatures = ::SecurityCenter::SecurityFeatures

      # Access
      before_action :organization_read_required
      before_action :security_center_required
      before_action :feature_flag_required
      before_action :security_features_required
      # For the prototype phase, we'll require security manager (or org owner) so we
      # can avoid the large `repository_id IN (...)` filter for accessible repos.
      before_action :manage_security_products_required

      # Ensure reconciliation
      after_action :ensure_security_overview_analytics_reconciliation, only: [:index]
      after_action :trigger_security_overview_analytics_backfill, only: [:index]

      sig { void }
      def index
        payload = log_timing(step: "build React payload") do
          feedback = ::SecurityCenter::FeedbackLink.new(
            phase: ::SecurityCenter::Phase.for_feature(:security_center_unified_alerts),
            actor: T.must(current_user),
            scope: this_organization,
          )

          {
            initial_query: params.key?(:query) ? query.to_s : nil,
            initial_group_key: params.fetch(:group_key, nil),
            feedback_link: {
              # TODO https://github.com/github/security-center/issues/5538
              # text: feedback.text,
              # url: feedback.url,
            },
            show_incomplete_data_warning: allowed_repos_capped?,
            incomplete_data_warning_doc_href: ::SecurityCenter::LimitedRepoWarningComponent::PERMISSIONS_DOC_HREF,
            custom_properties: ::SecurityCenter::Helpers::CustomProperties.new(org: this_organization, user: T.must(current_user)).definitions_for_frontend,
          }.to_camelback_keys
        end

        data = log_timing(step: "build locals") do
          {
            backfill_in_progress: this_organization.trigger_security_center_reconciliation,
            selected_tab: :unified_alerts,
          }
        end

        log_timing(step: "render") do
          render_react_app(
            app_name: "security-center",
            ssr: false,
            payload:,
            title: "Security · Alerts · #{this_organization.display_login}",
            layout: "layouts/security_center/with_sidebar",
            page_data: { data: },
            app_payload_generator: -> do
              {
                enabled_features: {
                  security_center_dashboards_show_severity_filter: ::SecurityCenter::FeatureFlagHelper.dashboards_show_filter?(:severity, *feature_flag_actors),
                }
              }
            end,
          )
        end
      end

      sig { void }
      def counts # rubocop:disable GitHub/UseRestfulActions
        result = log_timing(step: "build payload") do
          UnifiedAlerts::CountsDataQuery.for_organization(
            this_organization,
            user: T.must(current_user),
            user_session:,
            tools:,
            query:
          ).run
        end

        log_timing(step: "render") do
          # explicitly invoking `serialize` here to get a hash that can be camelized
          render_camelback_json(json: result.serialize)
        end
      end

      sig { void }
      def alerts # rubocop:disable GitHub/UseRestfulActions
        page_size = params.fetch(:page_size, 25).to_i

        result = log_timing(step: "build payload") do
          UnifiedAlerts::ListDataQuery.for_organization(
            this_organization,
            user: T.must(current_user),
            user_session:,
            tools:,
            query:
          ).run(cursor: params.fetch(:cursor, "0"), page_size:)
        end

        log_timing(step: "render") do
          # explicitly invoking `serialize` here to get a hash that can be camelized
          render_camelback_json(json: result.serialize)
        end
      end

      sig { void }
      def groups # rubocop:disable GitHub/UseRestfulActions
        group_key = params.fetch(:group_key, "")

        result = log_timing(step: "build payload") do
          UnifiedAlerts::GroupDataQuery.for_organization(
            this_organization,
            user: T.must(current_user),
            user_session:,
            tools:,
            query:
          ).run(group_key, cursor: params.fetch(:cursor, "0"))
        end

        log_timing(step: "render") do
          # explicitly invoking `serialize` here to get a hash that can be camelized
          render_camelback_json(json: result.serialize)
        end
      end

      private

      sig { returns([Organization, User]) }
      def feature_flag_actors
        [this_organization, T.must(current_user)]
      end

      sig { returns(T.untyped) }
      def feature_flag_required
        return if ::SecurityCenter::FeatureFlagHelper.show_unified_alerts?(*feature_flag_actors)
        return render_404 unless action_name == "index"
        redirect_to security_center_overview_dashboard_path(this_organization)
      end

      sig { returns(T.untyped) }
      def security_features_required
        visible_features = SecurityFeatures.visible_features(this_organization)
        return render_404 if visible_features.empty?
        render_404 unless visible_features.any? do |feature|
          if SecurityFeatures::SECRET_SCANNING == feature
            next ::SecretScanning::Features::Org::TokenScanning.new(this_organization).feature_available?
          end
          true
        end
      end

      sig { returns(T.untyped) }
      def manage_security_products_required
        render_404 unless can_manage_security_products?
      end

      sig { returns(::Search::Queries::SecurityCenter::QueryParser) }
      memoize def query
        ::Search::Queries::SecurityCenter::QueryParser.new(params.fetch(:query, ""))
      end

      sig { returns(T::Array[String]) }
      memoize def tools
        ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser.new(
          query: query,
          scope: this_organization,
          allowed_code_scanning_repo_ids: nil,
        ).selected_backend_security_features
      end

      sig { returns(T::Boolean) }
      def allowed_repos_capped?
        adminable_repo_ids.last
      end

      depends_on_clusters \
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Repositories,
        only: [
          :index
        ]

      depends_on_clusters \
        ApplicationRecord::Billing,
        ApplicationRecord::Copilot,
        ApplicationRecord::Mysql2,
        ApplicationRecord::Mysql5,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Notify,
        ApplicationRecord::SecurityOverviewAnalytics,
        optional: true,
        only: [
          :index
        ]

      depends_on_clusters \
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Notify,
        ApplicationRecord::Repositories,
        ApplicationRecord::SecurityOverviewAnalytics,
        only: [
          :counts,
          :alerts,
          :groups,
        ]

      instrument_method \
        :index,
        :counts,
        :alerts,
        :groups
    end
  end
end
