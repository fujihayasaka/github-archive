# typed: strict
# frozen_string_literal: true

module Businesses
  module SecurityCenter
    module Metrics
      class CodeScanningExportController < Businesses::SecurityCenter::AbstractSecurityCenterController
        extend T::Sig
        include ApplicationController::VerifiedFetchDependency
        include ::SecurityCenter::DateSpanControllerHelper
        include ::SecurityCenter::ExportControllerHelper

        CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
          "#{self}#create"
        ].freeze, T::Array[String])

        allow_verified_fetch only: [:create]

        # Access
        before_action :feature_required
        before_action :security_center_required
        before_action :feature_flag_required
        before_action :dotcom_required

        # Validation
        before_action :ensure_dates, only: [:create]
        before_action :ensure_query, only: [:create]

        sig { void }
        def show
          show_export
        end

        sig { void }
        def create
          create_export
        end

        private

        sig { override.returns(Business) }
        def scope
          this_business
        end

        sig { override.returns(String) }
        def feature_type
          ::SecurityOverviewAnalytics::CodeScanningPullRequestAlertsExportJob::FEATURE_TYPE
        end

        sig { override.returns(String) }
        def file_name_prefix
          "enterprise_#{feature_type}"
        end

        sig { override.params(export_id: String).returns(String) }
        def download_export_url(export_id)
          enterprise_security_center_metrics_codeql_export_path(export_id:, format: :csv)
        end

        sig { override.params(query: T.nilable(String)).returns(String) }
        def redirect_path(query)
          enterprise_security_center_metrics_codeql_path(this_business, query:)
        end

        sig { override.params(query: String, requested_at: Time, start_date_string: T.nilable(String), end_date_string: T.nilable(String)).returns(String) }
        def create_export_id(query, requested_at, start_date_string = nil, end_date_string = nil)
          canonical_query = ::Search::Queries::SecurityCenter::QueryParser.new(query).canonicalize
          ::SecurityCenter::Export::TokenGenerator.create_token(
            user: current_user,
            scope: this_business,
            query: canonical_query,
            feature_type:,
            requested_at:,
            start_date: (start_date_string ? Date.parse(start_date_string) : start_date),
            end_date: (end_date_string ? Date.parse(end_date_string) : end_date),
          )
        end

        sig { override.params(export_id: String, requested_at: T.nilable(Time)).returns(ExportJobStatus) }
        def create_job_status(export_id:, requested_at:)
          ExportJobStatus.create(id: export_id, query:, requested_at: requested_at, start_date:, end_date:)
        end

        sig { override.params(requested_at: Time, export_id: String, job_status: ExportJobStatus).void }
        def queue_job(requested_at, export_id, job_status)
          job_status.queued!
          job = SecurityOverviewAnalytics::CodeScanningPullRequestAlertsExportJob
            .enqueue_for_business(
              business: this_business,
              organizations: authorized_orgs,
              user: current_user,
              query_string: query,
              start_date: T.must(start_date),
              end_date: T.must(end_date),
              requested_at:,
            )

          unless job
            job_status.error!("We couldn't generate your report. Please try again later. If the problem persists, please contact support.")
            raise RuntimeError.new("Failed to create export job")
          end
        end

        # TODO move to superclass when we bring other exports to enterprise
        sig { override.params(event: String, event_payload: T.nilable(T::Hash[Symbol, T.untyped])).void }
        def instrument_audit_log_event(event:, event_payload: nil)
          payload = {
            scope: "business",
            business: this_business.display_login,
            business_id: this_business.id,
            user: current_user.display_login,
            user_id: current_user.id,
          }.merge(event_payload || {})

          GitHub.instrument(event, payload)
        end

        # TODO move to superclass when we bring other exports to enterprise
        sig { void }
        def ensure_query
          render json: { error: "Must provide a valid query" }, status: :bad_request unless params[:query]
        end

        sig { returns(T.untyped) }
        def feature_required
          render_404 unless ::SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance?
        end

        sig { void }
        def feature_flag_required
          render_404 unless ::SecurityCenter::FeatureFlagHelper.show_codeql_pr_alerts_export?(current_user, this_business)
        end

        sig { override.returns(T::Boolean) }
        def rate_limit_enabled?
          ::SecurityCenter::FeatureFlagHelper.csv_export_use_rate_limiter?(current_user, this_business)
        end

        sig { override.returns(String) }
        def user_rate_limit_key
          "security-center-export-#{feature_type}:#{current_user.id}-#{this_business.id}"
        end

        depends_on_clusters \
          ApplicationRecord::Collab,
          ApplicationRecord::Configurations,
          ApplicationRecord::Iam,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::Mysql1,
          ApplicationRecord::Mysql5,
          only: [
            :create,
          ]

        depends_on_clusters \
          ApplicationRecord::Copilot,
          ApplicationRecord::Mysql2,
          ApplicationRecord::NotificationsEntries,
          optional: true,
          only: [
            :create,
          ]

        depends_on_clusters \
          ApplicationRecord::Collab,
          ApplicationRecord::Configurations,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::Mysql1,
          ApplicationRecord::Mysql5,
          only: [
            :show,
          ]

        instrument_method \
          :create,
          :show
      end
    end
  end
end
