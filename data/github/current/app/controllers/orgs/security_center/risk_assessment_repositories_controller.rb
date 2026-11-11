# typed: strict
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    class RiskAssessmentRepositoriesController < Orgs::Controller
      depends_on_clusters \
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::Iam,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Repositories,
        ApplicationRecord::RepositoriesActionsChecks,
        ApplicationRecord::SecurityOverviewAnalytics,
        ApplicationRecord::SecurityProductsEnablement

      layout false

      before_action :login_required
      before_action :assessment_access_required
      before_action :code_security_risk_assessment_enabled?, only: [:scan, :csra_index]

      sig { void }
      def index
        render json: {
          items: sra_query.picker_repos,
          totalCount: sra_query.count,
        }
      end

      # Returns org repositories where Code Scanning is not yet enabled,
      # with committer data for cost estimation in the enablement repo picker.
      sig { void }
      def csra_index # rubocop:todo GitHub/UseRestfulActions
        query = csra_query
        render json: {
          items: query.picker_repos,
          totalCount: query.count,
        }
      end

      # Returns repositories eligible for code security scanning
      # Used by the repo picker when submitting a scan
      sig { void }
      def scan # rubocop:todo GitHub/UseRestfulActions
        render json: {
          eligibleRepos: code_security_risk_assessment_query.eligible_repos,
          totalEligibleRepoCount: code_security_risk_assessment_query.count,
          suggestedRepoIds: code_security_risk_assessment_query.suggested_repo_ids,
        }
      end

      private

      sig { returns(::SecurityProductsEnablement::CsraBulkEnablementQuery) }
      memoize def csra_query
        ::SecurityProductsEnablement::CsraBulkEnablementQuery.new(
          org: this_organization,
          actor: current_user,
          cap_filter:,
          remote_ip:,
          search_query: params[:q],
          user_session:,
        )
      end

      sig { returns(::SecurityProductsEnablement::CodeSecurityRiskAssessmentReposQuery) }
      memoize def code_security_risk_assessment_query
        ::SecurityProductsEnablement::CodeSecurityRiskAssessmentReposQuery.new(
          org: this_organization,
          actor: current_user,
          search_query: params[:q],
          cap_filter:,
          remote_ip:,
          user_session:,
        )
      end

      sig { returns(::SecretScanning::BulkEnablementQuery) }
      memoize def sra_query
        ::SecretScanning::BulkEnablementQuery.new(
          org: this_organization,
          actor: current_user,
          cap_filter:,
          remote_ip:,
          search_query: params[:q],
          user_session:,
          assessment_number: params[:assessment_id].to_i,
        )
      end

      sig { void }
      def code_security_risk_assessment_enabled?
        render_404 unless FeatureFlag.vexi.enabled?(:code_security_risk_assessment, this_organization, default: false)
      end

      sig { void }
      def assessment_access_required
        return render_404 unless this_organization

        access_control = ::SecurityProducts::AccessControl::RiskAssessments.new(this_organization)
        render_404 unless access_control.has_access_to_risk_assessments?(current_user)
      end
    end
  end
end
