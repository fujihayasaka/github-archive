# typed: strict
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    module Metrics
      class CodeScanningController < AbstractSecurityCenterController
        extend T::Sig
        include ReactHelper
        include ApplicationHelper
        include ::SecurityCenter::DateSpanControllerHelper

        # Access
        before_action :organization_read_required
        before_action :feature_required
        before_action :security_center_required

        # Validation
        before_action :ensure_dates, except: [:index]

        # Ensure reconciliation
        after_action :ensure_security_overview_analytics_reconciliation, only: [:index]
        after_action :trigger_security_overview_analytics_backfill, only: [:index]

        # Telemetry
        track_latency_slo "p99-ui-request", 2500, only: [:index]
        track_latency_slo "p50-ui-request", 750, only: [:index]
        track_availability_slo "ui-request", only: [:index]

        Queries = SecurityOverviewAnalytics::Dashboards::CodeScanningMetrics::Queries

        sig { void }
        def index
          payload = log_timing(step: "build React payload") do
            feedback = ::SecurityCenter::FeedbackLink.new(
              actor: T.must(current_user),
              scope: this_organization,
            )

            {
              initial_query: params.key?(:query) ? query.to_s : nil,
              initial_date_span:,
              watermark_date:,
              feedback_link: {
                text: feedback.text,
                url: feedback.url,
              },
              export_error_message: flash[:export_error],
              show_incomplete_data_warning: allowed_repository_ids_for_organization_members&.last,
              incomplete_data_warning_doc_href: ::SecurityCenter::LimitedRepoWarningComponent::PERMISSIONS_DOC_HREF,
              custom_properties: ::SecurityCenter::Helpers::CustomProperties.new(org: this_organization, user: T.must(current_user)).definitions_for_frontend,
              allow_autofix_features: CodeScanning::Autofix.enabled_for_org?(this_organization),
            }.to_camelback_keys
          end

          data = log_timing(step: "build locals") do
            {
              backfill_in_progress: this_organization.trigger_security_center_reconciliation,
              selected_tab: :code_scanning_metrics,
            }
          end

          log_timing(step: "render") do
            render_react_app(
              app_name: "security-center",
              ssr: false,
              payload:,
              title: "Security · Metrics · CodeQL Pull Request Alerts · #{this_organization.display_login}",
              layout: "layouts/security_center/with_sidebar",
              page_data: { data: },
              app_payload_generator: -> do
                {
                  enabled_features: {
                    security_center_dashboards_show_severity_filter: ::SecurityCenter::FeatureFlagHelper.dashboards_show_filter?(:severity, *feature_flag_actors),
                    security_center_dashboards_show_resolution_filter: ::SecurityCenter::FeatureFlagHelper.dashboards_show_filter?(:resolution, *feature_flag_actors),
                    security_center_show_codeql_pr_alerts_export: ::SecurityCenter::FeatureFlagHelper.show_codeql_pr_alerts_export?(*feature_flag_actors),
                  },
                }
              end,
            )
          end
        end

        sig { void }
        def alerts_found # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            Queries::AlertsFoundQuery.for_organization(
              organization: this_organization,
              allowed_repo_ids: allowed_repository_ids_for_organization_members&.first,
              user: T.must(current_user),
              user_session:,
              query:,
              start_date: T.must(start_date),
              end_date: T.must(end_date),
            ).perform
          end

          log_timing(step: "render") do
            render_camelback_json(json: payload.serialize)
          end
        end

        sig { void }
        def autofix_suggestions # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            Queries::AutofixSuggestionsQuery.for_organization(
              organization: this_organization,
              allowed_repo_ids: allowed_repository_ids_for_organization_members&.first,
              user: T.must(current_user),
              user_session:,
              query:,
              start_date: T.must(start_date),
              end_date: T.must(end_date),
            ).perform
          end

          log_timing(step: "render") do
            render_camelback_json(json: payload.serialize)
          end
        end

        sig { void }
        def alerts_fixed # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            Queries::AlertsFixedQuery.for_organization(
              organization: this_organization,
              allowed_repo_ids: allowed_repository_ids_for_organization_members&.first,
              user: T.must(current_user),
              user_session:,
              query:,
              start_date: T.must(start_date),
              end_date: T.must(end_date),
            ).perform
          end

          log_timing(step: "render") do
            render_camelback_json(json: payload.serialize)
          end
        end

        sig { void }
        def alert_trends_by_status # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            Queries::AlertTrendsQuery.for_organization(
              organization: this_organization,
              allowed_repo_ids: allowed_repository_ids_for_organization_members&.first,
              user: T.must(current_user),
              user_session:,
              query:,
              start_date: T.must(start_date),
              end_date: T.must(end_date),
            ).perform(group_by: Queries::AlertTrendsQuery::GroupOption::Status)
          end

          log_timing(step: "render") do
            render_camelback_json(json: payload.series.map(&:serialize))
          end
        end

        sig { void }
        def alert_trends_by_severity # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            Queries::AlertTrendsQuery.for_organization(
              organization: this_organization,
              allowed_repo_ids: allowed_repository_ids_for_organization_members&.first,
              user: T.must(current_user),
              user_session:,
              query:,
              start_date: T.must(start_date),
              end_date: T.must(end_date),
            ).perform(group_by: Queries::AlertTrendsQuery::GroupOption::Severity)
          end

          log_timing(step: "render") do
            render_camelback_json(json: payload.series.map(&:serialize))
          end
        end

        sig { void }
        def alerts_fixed_with_autofix # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            Queries::AlertsFixedWithAutofixQuery.for_organization(
              organization: this_organization,
              allowed_repo_ids: allowed_repository_ids_for_organization_members&.first,
              user: T.must(current_user),
              user_session:,
              query:,
              start_date: T.must(start_date),
              end_date: T.must(end_date),
            ).perform
          end

          log_timing(step: "render") do
            render_camelback_json(json: payload.serialize)
          end
        end

        sig { void }
        def remediation_rates # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            Queries::RemediationRatesQuery.for_organization(
              organization: this_organization,
              allowed_repo_ids: allowed_repository_ids_for_organization_members&.first,
              user: T.must(current_user),
              user_session:,
              query:,
              start_date: T.must(start_date),
              end_date: T.must(end_date),
            ).perform
          end

          log_timing(step: "render") do
            render_camelback_json(json: payload.serialize)
          end
        end

        sig { void }
        def most_prevalent_rules # rubocop:todo GitHub/UseRestfulActions
          cursor = params.fetch(:cursor, "0")
          page_size = params.fetch(:page_size, 10).to_i

          payload = log_timing(step: "build payload") do
            Queries::MostPrevalentRulesQuery.for_organization(
              organization: this_organization,
              allowed_repo_ids: allowed_repository_ids_for_organization_members&.first,
              user: T.must(current_user),
              user_session:,
              query:,
              start_date: T.must(start_date),
              end_date: T.must(end_date),
            ).perform(
              cursor:,
              page_size:,
            )
          end

          log_timing(step: "render") do
            render_camelback_json(json: payload.serialize)
          end
        end

        sig { void }
        def repositories # rubocop:todo GitHub/UseRestfulActions
          cursor = params.fetch(:cursor, "0")
          sort_field = Queries::RepositoriesTableQuery::SortField.try_deserialize(params[:sort_field])
          sort_direction = Queries::RepositoriesTableQuery::SortDirection.try_deserialize(params[:sort_direction])

          payload = log_timing(step: "build payload") do
            Queries::RepositoriesTableQuery.for_organization(
              organization: this_organization,
              allowed_repo_ids: allowed_repository_ids_for_organization_members&.first,
              user: T.must(current_user),
              user_session:,
              query:,
              start_date: T.must(start_date),
              end_date: T.must(end_date),
            ).perform(
              cursor:,
              sort_field:,
              sort_direction:,
            )
          end

          log_timing(step: "render") do
            render_camelback_json(json: payload.serialize)
          end
        end

        private

        sig { returns(T.untyped) }
        def feature_required
          render_404 unless ::SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance?
        end

        sig { returns(T.untyped) }
        def security_center_required
          render_404 unless ::SecurityCenter::SecurityFeatures.security_center_available?(this_organization, dotcom_request_only: true)
        end

        sig { returns([Organization, User]) }
        def feature_flag_actors
          [this_organization, T.must(current_user)]
        end

        sig { returns(::Search::Queries::SecurityCenter::QueryParser) }
        memoize def query
          ::Search::Queries::SecurityCenter::QueryParser.new(params.fetch(:query, ""))
        end

        sig { returns(T.nilable([T::Array[Integer], T::Boolean])) }
        memoize def allowed_repository_ids_for_organization_members
          return nil if can_manage_security_products?
          allowed_repository_ids_by_feature_for_organization_members[::SecurityCenter::SecurityFeatures::CODE_SCANNING]
        end

        depends_on_clusters \
          ApplicationRecord::Collab,
          ApplicationRecord::Configurations,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::Mysql1,
          ApplicationRecord::Repositories,
          only: [
            :index,
          ]

        depends_on_clusters \
          ApplicationRecord::Billing,
          ApplicationRecord::Iam,
          ApplicationRecord::Mysql2,
          ApplicationRecord::Mysql5,
          ApplicationRecord::NotificationsEntries,
          ApplicationRecord::Notify,
          ApplicationRecord::SecurityOverviewAnalytics,
          optional: true,
          only: [
            :index,
          ]

        depends_on_clusters \
          ApplicationRecord::Collab,
          ApplicationRecord::Configurations,
          ApplicationRecord::Iam,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::Mysql1,
          ApplicationRecord::Notify,
          ApplicationRecord::Repositories,
          ApplicationRecord::SecurityOverviewAnalytics,
          only: [
            :alerts_found,
            :autofix_suggestions,
            :alerts_fixed,
            :alert_trends_by_status,
            :alert_trends_by_severity,
            :alerts_fixed_with_autofix,
            :remediation_rates,
            :most_prevalent_rules,
            :repositories,
          ]

        depends_on_clusters \
          ApplicationRecord::Copilot,
          optional: true,
          only: [
            :index,
          ]

        instrument_method \
          :index,
          :alerts_found,
          :autofix_suggestions,
          :alerts_fixed,
          :alert_trends_by_status,
          :alert_trends_by_severity,
          :alerts_fixed_with_autofix,
          :remediation_rates,
          :most_prevalent_rules,
          :repositories,
          :allowed_repos_capped
      end
    end
  end
end
