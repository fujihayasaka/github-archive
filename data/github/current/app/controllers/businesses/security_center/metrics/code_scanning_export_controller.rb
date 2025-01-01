# typed: strict
# frozen_string_literal: true

module Businesses
  module SecurityCenter
    module Metrics
      class CodeScanningExportController < Businesses::SecurityCenter::AbstractSecurityCenterController
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
        before_action :dotcom_required

        # Validation
        before_action :ensure_dates, only: [:create]

        sig { void }
        def show
          super
        end

        sig { void }
        def create
          super
        end

        private

        sig { override.returns(Symbol) }
        def authorized_orgs_actions
          :read_code_scanning
        end

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
          ExportJobStatus.create(
            id: export_id,
            query:,
            scope: this_business,
            requester: current_user,
            requested_at:,
            start_date:,
            end_date:,
          )
        end

        sig { override.params(requested_at: Time, export_id: String, job_status: ExportJobStatus).returns(T.untyped) }
        def queue_job(requested_at, export_id, job_status)
          SecurityOverviewAnalytics::CodeScanningPullRequestAlertsExportJob
            .enqueue_for_business(
              business: this_business,
              organizations: authorized_orgs,
              user: current_user,
              export_id:
            )
        end

        sig { void }
        def feature_required
          render_404 unless ::SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance?
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
          ApplicationRecord::SecurityOverviewAnalytics,
          ApplicationRecord::Repositories,
          only: [:create]

        depends_on_clusters \
          ApplicationRecord::Copilot,
          ApplicationRecord::Mysql2,
          ApplicationRecord::NotificationsEntries,
          only: [:create],
          optional: true

        depends_on_clusters \
          ApplicationRecord::Collab,
          ApplicationRecord::Configurations,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::Mysql1,
          ApplicationRecord::Mysql5,
          ApplicationRecord::SecurityOverviewAnalytics,
          only: [:show]

        instrument_method \
          :create,
          :show
      end
    end
  end
end
