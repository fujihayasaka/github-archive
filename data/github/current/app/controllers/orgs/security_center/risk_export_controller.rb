# typed: strict
# frozen_string_literal: true

require "csv"
require "github/security_center/logging_helper"

module Orgs
  module SecurityCenter
    class RiskExportController < AbstractSecurityCenterController
      extend T::Sig
      include ApplicationController::VerifiedFetchDependency
      include ::SecurityCenter::ExportControllerHelper

      allow_verified_fetch only: [:create]

      # Access
      before_action :organization_read_required
      before_action :security_center_required
      before_action :dotcom_required

      # Telemetry
      before_action :set_failbot_context
      around_action :track_and_report_mysql_executions

      CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
        "#{self}#create"
      ].freeze, T::Array[String])

      sig { void }
      def show
        show_export
      end

      sig { void }
      def create
        create_export
      end

      private

      sig { override.returns(Organization) }
      def scope
        this_organization
      end

      sig { override.returns(String) }
      def feature_type
        "risk"
      end

      sig { override.returns(String) }
      def file_name_prefix
        "organization_security_risk"
      end

      sig { override.params(export_id: String).returns(String) }
      def download_export_url(export_id)
        security_center_risk_get_export_path(export_id:, format: :csv)
      end

      sig { override.params(query: T.nilable(String)).returns(String) }
      def redirect_path(query)
        security_center_risk_path(this_organization, query:)
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
        )
      end

      sig { override.params(export_id: String, requested_at: T.nilable(Time)).returns(ExportJobStatus) }
      def create_job_status(export_id:, requested_at:)
        ExportJobStatus.create(id: export_id, query:, requested_at: requested_at)
      end

      sig { override.params(requested_at: Time, export_id: String, job_status: ExportJobStatus).void }
      def queue_job(requested_at, export_id, job_status)
        job = ::SecurityCenter::RiskExportJob.perform_later(
          scope: this_organization,
          user: current_user,
          user_session: user_session,
          query_string: query,
          requested_at:,
        )

        raise RuntimeError.new("Failed to create export job") unless job

        job_status.queued!
      end

      sig { override.returns(String) }
      memoize def query
        params[:query] || RiskController::DEFAULT_QUERY
      end

      sig { override.returns(T::Boolean) }
      def rate_limit_enabled?
        ::SecurityCenter::FeatureFlagHelper.csv_export_use_rate_limiter?(current_user, this_organization)
      end

      sig { override.returns(String) }
      def user_rate_limit_key
        "security-center-export-risk:#{current_user.id}-#{this_organization.id}"
      end

      instrument_method :show, :create

      depends_on_clusters \
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Mysql5,
        only: [:show, :create]

      depends_on_clusters \
        ApplicationRecord::Billing,
        ApplicationRecord::Iam,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Notify,
        ApplicationRecord::Repositories,
        only: [:create]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:create], optional: true
    end
  end
end
