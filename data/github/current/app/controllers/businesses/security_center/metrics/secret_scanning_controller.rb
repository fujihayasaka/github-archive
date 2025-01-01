# typed: strict
# frozen_string_literal: true

module Businesses
  module SecurityCenter
    module Metrics
      class SecretScanningController < AbstractSecurityCenterController
        include ApplicationHelper
        include ApplicationController::VerifiedFetchDependency
        include ::SecurityCenter::DateSpanControllerHelper
        include ::SecretScanningControllerHelper

        before_action :security_center_required
        before_action :secret_scanning_required
        before_action :ensure_dates, except: [:index]

        after_action :ensure_security_center_reconciliation, only: [:index]
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
          route_payload = log_timing(step: "build React payload") do
            unless authorized_orgs.blank?
              feedback = ::SecurityCenter::FeedbackLink.new(
                actor: current_user,
                scope: this_business,
              )

              {
                initial_query: params.key?(:query) ? query_parser.to_s : nil,
                initial_date_span:,
                custom_properties: [], # TODO: Implement business version of `SecurityCenter::Helpers::CustomProperties` and use here
                feedback_url: feedback.url,
                feedback_text: feedback.text,
                allow_owner_type_filtering: can_see_personal_repos?,
              }.deep_transform_keys { |key| key.to_s.camelize(:lower) }
            end
          end

          app_payload_generator = log_timing(step: "build app payload") do
            if route_payload.nil? || show_blankslate
              blankslate_app_payload_generator(
                heading: "Secret scanning",
                message: "No repositories to show.",
                description: blankslate_description,
                # TODO: Need a doc link
                # learn_more_link: {
                #   text: "Learn more about viewing the overview page.",
                #   url: "#",
                # },
              )
            else
              content_app_payload_generator
            end
          end

          log_timing(step: "render") do
            render_react_app(
              app_name: "security-center",
              disable_ssr: true,
              payload: route_payload,
              page_data: { selected_link: :business_secret_scanning_metrics, sidebar: :code_security },
              title: "Security · Metrics · Secret Scanning · #{this_business}",
              app_payload_generator:,
            )
          end
        end

        sig { void }
        def push_protection_metrics # rubocop:disable GitHub/UseRestfulActions
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
        def block_counts_by_token_type # rubocop:disable GitHub/UseRestfulActions
          cursor, success = cursor_from_params
          return render json: { error: "Invalid pagination cursor" }, status: 422 unless success

          metrics = query_service.get_block_counts_by_token_type(cursor:)
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
        def block_counts_by_repo # rubocop:disable GitHub/UseRestfulActions
          cursor, success = cursor_from_params
          return render json: { error: "Invalid pagination cursor" }, status: 422 unless success

          metrics = query_service.get_block_counts_by_repo(cursor:)
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
        def bypass_counts_by_token_type # rubocop:disable GitHub/UseRestfulActions
          cursor, success = cursor_from_params
          return render json: { error: "Invalid pagination cursor" }, status: 422 unless success

          metrics = query_service.get_bypass_counts_by_token_type(cursor:)
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
        def bypass_counts_by_repo # rubocop:disable GitHub/UseRestfulActions
          cursor, success = cursor_from_params
          return render json: { error: "Invalid pagination cursor" }, status: 422 unless success

          metrics = query_service.get_bypass_counts_by_repo(cursor:)
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

        sig { override.returns(Symbol) }
        def authorized_orgs_actions
          :view_secret_scanning_alerts
        end

        sig { void }
        def secret_scanning_required
          token_scanning = ::SecretScanning::Features::Business::TokenScanning.new(this_business)
          render_404 unless token_scanning.feature_available?
        end

        sig { returns([Business, User]) }
        memoize def feature_flag_actors
          [this_business, current_user]
        end

        sig { returns(::Search::Queries::SecurityCenter::QueryParser) }
        memoize def query_parser
          ::Search::Queries::SecurityCenter::QueryParser.new(params.fetch(:query, ""))
        end

        sig { returns(::SecurityCenter::QueryServices::SecretScanningMetrics) }
        memoize def query_service
          ::SecurityCenter::QueryServices::SecretScanningMetrics.new(
            scope: this_business,
            user: current_user,
            user_session:,
            query_parser:,
            start_date:,
            end_date:,
            authorized_orgs:
          )
        end

        sig { returns(::SecretScanning::Models::React::MetricsPayloadBuilder) }
        memoize def payload_builder
          ::SecretScanning::Models::React::MetricsPayloadBuilder.new
        end

        depends_on_clusters ApplicationRecord::SecurityOverviewAnalytics

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
            :push_protection_metrics,
            :block_counts_by_token_type,
            :block_counts_by_repo,
            :bypass_counts_by_token_type,
            :bypass_counts_by_repo
          ]

        depends_on_clusters \
          ApplicationRecord::Copilot,
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
