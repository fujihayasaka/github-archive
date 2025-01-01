# typed: strict
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    module Metrics
      class SecretScanningExportController < AbstractSecurityCenterController
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

        sig { override.returns(Organization) }
        def scope
          this_organization
        end

        sig { override.returns(String) }
        def feature_type
          "secret_scanning_metrics"
        end

        sig { override.returns(String) }
        def file_name_prefix
          "organization_#{feature_type}"
        end

        sig { override.params(export_id: String).returns(String) }
        def download_export_url(export_id)
          security_center_metrics_secret_scanning_get_export_path(export_id:, format: :csv)
        end

        sig { override.params(query: T.nilable(String)).returns(String) }
        def redirect_path(query)
          security_center_secret_scanning_metrics_path(this_organization, query:)
        end

        sig { override.params(query: String, requested_at: Time, start_date_string: T.nilable(String), end_date_string: T.nilable(String)).returns(String) }
        def create_export_id(query, requested_at, start_date_string = nil, end_date_string = nil)
          canonical_query = ::Search::Queries::SecurityCenter::QueryParser.new(query).canonicalize
          ::SecurityCenter::Export::TokenGenerator.create_token(
            user: current_user,
            scope: this_organization,
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
            scope: this_organization,
            requester: current_user,
            requested_at:,
            start_date:,
            end_date:,
          )
        end

        sig { override.params(requested_at: Time, export_id: String, job_status: ExportJobStatus).returns(T.untyped) }
        def queue_job(requested_at, export_id, job_status)
          # TODO: Create job https://github.com/github/security-center/issues/6120
          # SecurityOverviewAnalytics::SecretScanningPushProtectionAlertsExportJob
          #   .enqueue_for_organization(
          #     organization: this_organization,
          #     allowed_repo_ids:,
          #     user: current_user,
          #     user_session:,
          #     export_id:
          #   )
        end

        sig { returns(T.untyped) }
        def feature_required
          token_scanning = ::SecretScanning::Features::Org::TokenScanning.new(this_organization)
          render_404 unless ::SecurityCenter::FeatureFlagHelper.org_secret_scanning_csv_export?(current_user, this_organization) && token_scanning.feature_available?
        end

        sig { override.returns(String) }
        def user_rate_limit_key
          "security-center-export-#{feature_type}:#{current_user.id}-#{this_organization.id}"
        end

        depends_on_clusters \
          ApplicationRecord::Collab,
          ApplicationRecord::Configurations,
          ApplicationRecord::Iam,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::Mysql1,
          ApplicationRecord::Mysql5,
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
          only: [:show]

        instrument_method \
          :create,
          :show
      end
    end
  end
end
