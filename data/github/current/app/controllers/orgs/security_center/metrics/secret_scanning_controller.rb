# typed: strict
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    module Metrics
      class SecretScanningController < AbstractSecurityCenterController
        include ApplicationHelper
        include ReactHelper
        include ApplicationController::VerifiedFetchDependency
        include ::SecurityCenter::DateSpanControllerHelper

        before_action :organization_read_required
        before_action :feature_required
        before_action :security_center_required
        before_action :ensure_dates, except: [:index]

        after_action :ensure_security_overview_analytics_reconciliation, only: [:index]
        after_action :trigger_security_overview_analytics_backfill, only: [:index]

        allow_verified_fetch only: [
          :push_protection_metrics,
          :block_counts_by_token_type,
          :block_counts_by_repo,
          :bypass_counts_by_token_type,
          :bypass_counts_by_repo
        ]

        sig { void }
        def index
          feedback = ::SecurityCenter::FeedbackLink.new(actor: T.must(current_user), scope: this_organization)
          show_incomplete_data_warning = !!allowed_repository_ids_for_organization_members&.last

          data = log_timing(step: "build locals") do
            {
              backfill_in_progress: this_organization.trigger_security_center_reconciliation,
              selected_tab: :secret_scanning_metrics,
            }
          end

          payload = {
            initial_query: params.key?(:query) ? query_parser.to_s : nil,
            initial_date_span:,
            custom_properties: ::SecurityCenter::Helpers::CustomProperties.new(
              org: this_organization,
              user: T.must(current_user)
            ).definitions_for_frontend,
            feedback_url: feedback.url,
            feedback_text: feedback.text,
            show_incomplete_data_warning:,
            incomplete_data_warning_doc_href: ::SecurityCenter::LimitedRepoWarningComponent::PERMISSIONS_DOC_HREF,
            show_csv_export: !GitHub.enterprise? && ::SecurityCenter::FeatureFlagHelper.org_secret_scanning_csv_export?(*feature_flag_actors),
            export_error_message: flash[:export_error],
          }

          log_timing(step: "render") do
            render_react_app(
              app_name: "security-center",
              ssr: false,
              payload: payload.to_camelback_keys,
              title: "Security · Metrics · Secret Scanning · #{this_organization.display_login}",
              layout: "layouts/security_center/with_sidebar",
              page_data: { data: },
              app_payload_generator: -> do
                { enabled_features: {} }
              end,
            )
          end
        end

        sig { void }
        def push_protection_metrics # rubocop:todo GitHub/UseRestfulActions
          metrics, error = query_service.get_push_protection_metrics
          if error
            ::SecretScanning::Util::Stats.track_graceful_failure(env)
          end

          return render_camelback_json(json: {}, status: :internal_server_error) if error

          json = if metrics.is_a?(::SecurityCenter::QueryServices::SecretScanningMetrics::NoDataResponse)
            metrics.serialize
          else
            { payload: payload_builder.push_protection_metrics(metrics) }
          end

          log_timing(step: "render") do
            render_camelback_json(json:)
          end
        end

        sig { void }
        def block_counts_by_token_type # rubocop:todo GitHub/UseRestfulActions
          metrics = query_service.get_block_counts_by_token_type(cursor: params[:cursor])
          if metrics.nil?
            ::SecretScanning::Util::Stats.track_graceful_failure(env)
          end

          return render_camelback_json(json: {}, status: :internal_server_error) if metrics.nil?

          payload = payload_builder.token_type_counts(metrics)

          log_timing(step: "render") do
            render_camelback_json(json: { payload: })
          end
        end

        sig { void }
        def block_counts_by_repo # rubocop:todo GitHub/UseRestfulActions
          metrics = query_service.get_block_counts_by_repo(cursor: params[:cursor])
          if metrics.nil?
            ::SecretScanning::Util::Stats.track_graceful_failure(env)
          end

          return render_camelback_json(json: {}, status: :internal_server_error) if metrics.nil?

          payload = payload_builder.repo_counts(metrics)

          log_timing(step: "render") do
            render_camelback_json(json: { payload: })
          end
        end

        sig { void }
        def bypass_counts_by_token_type # rubocop:todo GitHub/UseRestfulActions
          metrics = query_service.get_bypass_counts_by_token_type(cursor: params[:cursor])
          if metrics.nil?
            ::SecretScanning::Util::Stats.track_graceful_failure(env)
          end

          return render_camelback_json(json: {}, status: :internal_server_error) if metrics.nil?

          payload = payload_builder.token_type_counts(metrics)

          log_timing(step: "render") do
            render_camelback_json(json: { payload: })
          end
        end

        sig { void }
        def bypass_counts_by_repo # rubocop:todo GitHub/UseRestfulActions
          metrics = query_service.get_bypass_counts_by_repo(cursor: params[:cursor])
          if metrics.nil?
            ::SecretScanning::Util::Stats.track_graceful_failure(env)
          end

          return render_camelback_json(json: {}, status: :internal_server_error) if metrics.nil?

          payload = payload_builder.repo_counts(metrics)

          log_timing(step: "render") do
            render_camelback_json(json: { payload: })
          end
        end

        private

        sig { returns([Organization, User]) }
        memoize def feature_flag_actors
          [this_organization, T.must(current_user)]
        end

        sig { void }
        def feature_required
          token_scanning = ::SecretScanning::Features::Org::TokenScanning.new(this_organization)
          render_404 unless token_scanning.feature_available?
        end

        sig { returns(::Search::Queries::SecurityCenter::QueryParser) }
        memoize def query_parser
          ::Search::Queries::SecurityCenter::QueryParser.new(params.fetch(:query, ""))
        end

        sig { returns(::SecurityCenter::QueryServices::SecretScanningMetrics) }
        memoize def query_service
          ::SecurityCenter::QueryServices::SecretScanningMetrics.new(
            scope: this_organization,
            user: T.must(current_user),
            user_session:,
            query_parser:,
            start_date:,
            end_date:,
            allowed_repo_ids: allowed_repository_ids_for_organization_members&.first
          )
        end

        sig { returns(T.nilable([T::Array[Integer], T::Boolean])) }
        memoize def allowed_repository_ids_for_organization_members
          return nil if can_view_all_alerts?
          allowed_repository_ids_by_feature_for_organization_members[::SecurityCenter::SecurityFeatures::SECRET_SCANNING]
        end

        sig { returns(::SecretScanning::Models::React::MetricsPayloadBuilder) }
        memoize def payload_builder
          ::SecretScanning::Models::React::MetricsPayloadBuilder.new
        end

        depends_on_clusters \
          ApplicationRecord::Billing,
          ApplicationRecord::Collab,
          ApplicationRecord::Configurations,
          ApplicationRecord::Iam,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::Mysql1,
          ApplicationRecord::Mysql2,
          ApplicationRecord::Mysql5,
          ApplicationRecord::NotificationsEntries,
          ApplicationRecord::Notify,
          ApplicationRecord::Repositories,
          only: [:index]

        depends_on_clusters \
          ApplicationRecord::Collab,
          ApplicationRecord::Configurations,
          ApplicationRecord::Iam,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::Mysql1,
          ApplicationRecord::Notify,
          ApplicationRecord::Repositories,
          only: [
            :block_counts_by_repo,
            :block_counts_by_token_type,
            :bypass_counts_by_repo,
            :bypass_counts_by_token_type,
            :push_protection_metrics,
          ]

        depends_on_clusters \
          ApplicationRecord::Copilot,
          ApplicationRecord::SecurityOverviewAnalytics,
          only: [:index],
          optional: true

        instrument_method \
          :index,
          :push_protection_metrics,
          :block_counts_by_token_type,
          :block_counts_by_repo,
          :bypass_counts_by_token_type,
          :bypass_counts_by_repo
      end
    end
  end
end
