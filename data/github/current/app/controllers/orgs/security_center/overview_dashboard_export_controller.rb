# typed: strict
# frozen_string_literal: true

require "csv"
require "github/security_center/logging_helper"

module Orgs
  module SecurityCenter
    class OverviewDashboardExportController < AbstractSecurityCenterController
      include ApplicationController::VerifiedFetchDependency
      include ::SecurityCenter::DateSpanControllerHelper
      include ::SecurityCenter::ExportControllerHelper

      CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
        "#{self}#create"
      ].freeze, T::Array[String])

      allow_verified_fetch only: [:create]

      # Access
      before_action :organization_read_required
      before_action :security_center_required
      before_action :dotcom_required

      before_action :ensure_dates, only: [:create]

      # Telemetry
      before_action :set_failbot_context
      around_action :track_and_report_mysql_executions

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
        "overview_dashboard"
      end

      sig { override.returns(String) }
      def file_name_prefix
        "organization_security_overview_alerts"
      end

      sig { override.params(export_id: String).returns(String) }
      def download_export_url(export_id)
        security_center_overview_dashboard_get_export_path(export_id:, format: :csv)
      end

      sig { override.params(query: T.nilable(String)).returns(String) }
      def redirect_path(query)
        security_center_overview_dashboard_path(this_organization, query:)
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
        security_features_parser = ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser.new(
          query: Search::Queries::SecurityCenter::QueryParser.new(query),
          scope: this_organization,
          allowed_code_scanning_repo_ids: can_view_all_alerts? ? nil : allowed_repository_ids_by_feature_for_organization_members[::SecurityCenter::SecurityFeatures::CODE_SCANNING]&.first,
        )

        features_by_table = []
        features_by_table << [::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS] if security_features_parser.selected_backend_security_features.include?(::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS)
        features_by_table << [::SecurityCenter::SecurityFeatures::SECRET_SCANNING] if security_features_parser.selected_backend_security_features.include?(::SecurityCenter::SecurityFeatures::SECRET_SCANNING)
        code_scanning_features = security_features_parser.selected_backend_security_features - [::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS, ::SecurityCenter::SecurityFeatures::SECRET_SCANNING]
        features_by_table << code_scanning_features if code_scanning_features.present?

        if features_by_table.empty?
          raise ExportUserFacingError.new("We couldn't generate your report. Please select at least one security tool.")
        end

        ::SecurityCenter::OverviewDashboardExportBatchedJob.perform_later(
          scope: this_organization,
          user: current_user,
          security_feature: features_by_table.pop,
          features_to_process: features_by_table,
          user_session:,
          offset_item_id: 0,
          is_first_feature: true,
          export_id:
        )
      end

      sig { override.returns(String) }
      def user_rate_limit_key
        "security-center-export-overview:#{current_user.id}-#{this_organization.id}"
      end

      instrument_method :show, :create

      depends_on_clusters \
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Mysql5,
        ApplicationRecord::SecurityOverviewAnalytics,
        only: [:show, :create]

      depends_on_clusters \
        ApplicationRecord::Billing,
        ApplicationRecord::Iam,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Notify,
        ApplicationRecord::Repositories,
        only: [:create]

      depends_on_clusters \
        ApplicationRecord::Copilot,
        only: [:create],
        optional: true
    end
  end
end
