# typed: strict
# frozen_string_literal: true

require "csv"
require "github/security_center/logging_helper"

module Businesses
  module SecurityCenter
    class CoverageExportController < AbstractSecurityCenterController
      include ApplicationController::VerifiedFetchDependency
      include ::SecurityCenter::ExportControllerHelper

      CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
        "#{self}#create"
      ].freeze, T::Array[String])

      allow_verified_fetch only: [:create]

      # Access
      before_action :security_center_required
      before_action :dotcom_required

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

      sig { override.returns(Symbol) }
      def authorized_orgs_actions
        if FeatureFlag.vexi.enabled?("security_products_fgp_split", default: false)
          :manage_repo_security_products
        else
          :manage_security_products
        end
      end

      sig { override.returns(Business) }
      def scope
        this_business
      end

      sig { override.returns(String) }
      def feature_type
        "coverage"
      end

      sig { override.returns(String) }
      def file_name_prefix
        "enterprise_security_coverage"
      end

      sig { override.params(export_id: String).returns(String) }
      def download_export_url(export_id)
        security_center_coverage_get_export_enterprise_path(export_id:, format: :csv)
      end

      sig { override.params(query: T.nilable(String)).returns(String) }
      def redirect_path(query)
        security_center_coverage_enterprise_path(this_business, query:)
      end

      sig { override.params(query: String, requested_at: Time, start_date_string: T.nilable(String), end_date_string: T.nilable(String)).returns(String) }
      def create_export_id(query, requested_at, start_date_string = nil, end_date_string = nil)
        canonical_query = ::Search::Queries::SecurityCenter::CoverageQueryParser.new(query).canonicalize
        ::SecurityCenter::Export::TokenGenerator.create_token(
          user: current_user,
          scope: this_business,
          query: canonical_query,
          feature_type:,
          requested_at:,
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
        )
      end

      sig { override.params(requested_at: Time, export_id: String, job_status: ExportJobStatus).returns(T.untyped) }
      def queue_job(requested_at, export_id, job_status)
        ::SecurityCenter::CoverageExportBatchedJob.perform_later(
          scope: this_business,
          user: current_user,
          export_id:,
          user_session:,
          authorized_orgs:,
        )
      end

      sig { override.returns(String) }
      def user_rate_limit_key
        "security-center-export-coverage:#{current_user.id}-#{this_business.id}"
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

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:create],
        optional: true
    end
  end
end
