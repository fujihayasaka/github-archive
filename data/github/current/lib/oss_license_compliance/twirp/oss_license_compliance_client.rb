# typed: true
# frozen_string_literal: true

### Based on lib/dependency_graph_platform/twirp/sbom_client.rb

require_relative "oss_license_compliance_connection"

# Extension of Sorbet generated files.  Methods were not part of the generated files.

module OSSLicenseCompliance
  module Twirp
    class OSSLicenseComplianceClient < OSSLicenseCompliance::Twirp::OSSLicenseComplianceConnection
      DEFAULT_READ_TIMEOUT = GitHub.default_request_timeout
      MESSAGE_PATH = "github.osscompliance_service.LicenseCompliance"

      sig do
        params(
          enterprise_id: Integer,
          context: T.nilable(String),
          spdx_ids: T.nilable(T::Array[String]),
          user_id: T.nilable(Integer)
        ).returns(OSSLicenseCompliance::V0::AddLicensesToEnterprisePolicyResponse)
      end
      def add_licenses_to_enterprise_policy(enterprise_id:, context: nil, spdx_ids: nil, user_id: nil)
        request = {
          enterprise_id: enterprise_id,
          spdx_ids:      spdx_ids,
          context:       context,
          user_id:       user_id,
        }
        rpc(:AddLicensesToEnterprisePolicy, request)
      end

      sig do
        params(
          enterprise_id: Integer,
          context: T.nilable(String),
          spdx_ids: T.nilable(T::Array[String])
        ).returns(OSSLicenseCompliance::V0::DeleteLicensesFromEnterprisePolicyResponse)
      end
      def delete_licenses_from_enterprise_policy(enterprise_id:, context: nil, spdx_ids: nil)
        request = {
          enterprise_id: enterprise_id,
          spdx_ids:      spdx_ids,
          context:       context,
        }
        rpc(:DeleteLicensesFromEnterprisePolicy, request)
      end

      sig do
        params(
          context: T.nilable(String),
          organization_id: T.nilable(Integer),
          spdx_ids: T.nilable(T::Array[String]),
          user_id: T.nilable(Integer)
        ).returns(OSSLicenseCompliance::V0::AddLicensesToOrganizationPolicyResponse)
      end
      def add_licenses_to_organization_policy(context: nil, organization_id: nil, spdx_ids: nil, user_id: nil)
        request = {
          organization_id: organization_id,
          spdx_ids:        spdx_ids,
          context:         context,
          user_id:         user_id,
        }
        rpc(:AddLicensesToOrganizationPolicy, request)
      end

      sig do
        params(
          repository_id: T.nilable(Integer),
          spdx_ids: T.nilable(T::Array[String])
        ).returns(OSSLicenseCompliance::V0::DeleteLicensesFromRepositoryPolicyResponse)
      end
      def delete_licenses_from_repository_policy(repository_id: nil, spdx_ids: nil)
        request = {
          repository_id: repository_id,
          spdx_ids:      spdx_ids,
        }
        rpc(:DeleteLicensesFromRepositoryPolicy, request)
      end

      sig do
        params(
          enterprise_id: Integer,
          licenses:      T.nilable(Hash),
          packages:      T.nilable(T::Array[Hash]),
        ).returns(OSSLicenseCompliance::V0::CreateEnterprisePolicyResponse)
      end
      def create_enterprise_policy(enterprise_id:, licenses: nil, packages: nil)
        request = {
          enterprise_id: enterprise_id,
          licenses:      licenses,
          packages:      packages,
        }
        rpc(:CreateEnterprisePolicy, request)
      end

      sig { params(enterprise_id: Integer).returns(OSSLicenseCompliance::V0::GetEnterprisePolicyResponse) }
      def get_enterprise_policy(enterprise_id:)
        rpc_request = {
          enterprise_id: enterprise_id,
        }
        rpc(:GetEnterprisePolicy, rpc_request)
      end

      sig do
        params(
          repository_id:   Integer,
          commit_sha:      T.nilable(String),
          base_sha:        T.nilable(String),
          organization_id: T.nilable(Integer),
          enterprise_id:   T.nilable(Integer),
          pull_request_id: T.nilable(Integer),
          pull_request_number: T.nilable(Integer)
        ).returns(OSSLicenseCompliance::V0::CheckRepositoryResponse)
      end
      def check_repository(repository_id:, commit_sha: nil, base_sha: nil, organization_id: nil, enterprise_id: 0, pull_request_id: 0, pull_request_number: 0)
        rpc_request = {
          enterprise_id:   enterprise_id,
          organization_id: organization_id,
          repository_id:   repository_id,
          commit_sha:      commit_sha,
          base_sha:        base_sha,
          pull_request_id: pull_request_id,
          pull_request_number: pull_request_number
        }
        rpc(:CheckRepository, rpc_request)
      end

      sig do
        params(
          comment: T.nilable(String),
          number: T.nilable(Integer),
          repository_id: T.nilable(Integer),
          user_id: T.nilable(Integer)
        ).returns(OSSLicenseCompliance::V0::DenyAlertDismissalResponse)
      end
      def deny_alert_dismissal(comment: nil, number: nil, repository_id: nil, user_id: nil)
        rpc_request = {
          comment:       comment,
          number:        number,
          repository_id: repository_id,
          user_id:       user_id
        }
        rpc(:DenyAlertDismissal, rpc_request)
      end

      sig { params(repository_id: Integer, number: Integer).returns(OSSLicenseCompliance::V0::GetAlertResponse) }
      def get_alert(repository_id:, number:)
        rpc_request = {
          repository_id: repository_id,
          number: number
        }
        rpc(:GetAlert, rpc_request)
      end

      sig do
        params(
          organization_id: T.nilable(Integer),
          enterprise_id: T.nilable(Integer)
        ).returns(OSSLicenseCompliance::V0::GetReviewableAlertsResponse)
      end
      def get_reviewable_alerts(organization_id: nil, enterprise_id: nil)
        rpc_request = {
          organization_id: organization_id,
          enterprise_id: enterprise_id
        }
        rpc(:GetReviewableAlerts, rpc_request)
      end

      sig do
        params(
          repository_id: Integer,
          number: Integer,
          user_id: Integer,
          closure_reason: T.nilable(Symbol),
          comment: T.nilable(String)
        ).returns(OSSLicenseCompliance::V0::RequestAlertDismissalResponse)
      end
      def request_alert_dismissal(repository_id:, number:, user_id:, closure_reason: nil, comment: nil)
        rpc_request = {
          repository_id: repository_id,
          number: number,
          user_id: user_id,
          closure_reason: closure_reason,
          comment: comment
        }
        rpc(:RequestAlertDismissal, rpc_request)
      end

      sig do
        params(
          alert_id: Integer,
          user_id: Integer,
          closure_reason: T.nilable(Symbol),
          comment: T.nilable(String)
        ).returns(OSSLicenseCompliance::V0::RequestAlertDismissalByIdResponse)
      end
      def request_alert_dismissal_by_id(alert_id:, user_id:, closure_reason: nil, comment: nil)
        rpc_request = {
          alert_id: alert_id,
          user_id: user_id,
          closure_reason: closure_reason,
          comment: comment
        }
        rpc(:RequestAlertDismissalById, rpc_request)
      end

      sig do
        params(
          user_id:         Integer,
          alert_number:    Integer,
          policy_level:    Symbol,
          contexts:        T::Array[String],
          comment:         String,
          action: T.nilable(Symbol),
          pattern: T.nilable(String),
          repository_id:   T.nilable(Integer),
          organization_id: T.nilable(Integer),
          enterprise_id:   T.nilable(Integer),
        ).returns(OSSLicenseCompliance::V0::CreatePackageExceptionResponse)
      end
      def create_package_exception(user_id:, alert_number:, policy_level:, contexts:, comment:, action:, pattern:, repository_id: nil, organization_id: nil, enterprise_id: nil)
        rpc_request = {
          repository_id: repository_id,
          organization_id: organization_id,
          enterprise_id: enterprise_id,
          user_id: user_id,
          alert_number: alert_number,
          policy_level: policy_level,
          contexts: contexts,
          comment: comment,
          action: action,
          pattern: pattern
        }
        rpc(:CreatePackageException, rpc_request)
      end

      sig do
        params(
           enterprise_id: Integer,
           packages: T::Array[Hash]
        ).returns(OSSLicenseCompliance::V0::DeletePackageExceptionsFromEnterprisePolicyResponse)
      end
      def delete_package_exceptions_from_enterprise_policy(enterprise_id:, packages:)
        rpc_request = {
          enterprise_id: enterprise_id,
          packages: packages
        }
        rpc(:DeletePackageExceptionsFromEnterprisePolicy, rpc_request)
      end

      sig do
        params(
          repository_id: Integer,
          packages: T::Array[Hash]
        ).returns(OSSLicenseCompliance::V0::DeletePackageExceptionsFromRepositoryPolicyResponse)
      end
      def delete_package_exceptions_from_repository_policy(repository_id:, packages:)
        rpc_request = {
          repository_id: repository_id,
          packages: packages
        }
        rpc(:DeletePackageExceptionsFromRepositoryPolicy, rpc_request)
      end

      sig do
        params(
          alert_number: Integer,
          user_id: Integer,
          policy_level: Symbol,
          contexts: T::Array[String],
          comment: String,
          repository_id: T.nilable(Integer),
          organization_id: T.nilable(Integer),
          enterprise_id: T.nilable(Integer)
        ).returns(OSSLicenseCompliance::V0::AddLicensesForAlertResponse)
      end
      def add_licenses_for_alert(alert_number:, user_id:, policy_level:, contexts:, comment:, repository_id: nil, organization_id: nil, enterprise_id: nil)
        rpc_request = {
          alert_number: alert_number,
          user_id: user_id,
          policy_level: policy_level,
          contexts: contexts,
          comment: comment,
          repository_id: repository_id,
          organization_id: organization_id,
          enterprise_id: enterprise_id
        }
        rpc(:AddLicensesForAlert, rpc_request)
      end

      sig do
        params(
          distribution_policy_name: T.nilable(String),
          enterprise_id: T.nilable(Integer),
          organization_id: T.nilable(Integer),
          repository_id: T.nilable(Integer)
        ).returns(OSSLicenseCompliance::V0::GetCombinedRepositoryPolicyResponse)
      end
      def get_combined_repository_policy(distribution_policy_name: nil, enterprise_id: nil,  organization_id: nil, repository_id: nil)
        rpc_request = {
          distribution_policy_name: distribution_policy_name,
          enterprise_id: enterprise_id,
          organization_id: organization_id,
          repository_id: repository_id
        }
        rpc(:GetCombinedRepositoryPolicy, rpc_request)
      end

      sig do
        params(
          repository_id: Integer,
          number: Integer,
          expiry_timestamp: Google::Protobuf::Timestamp
        ).returns(OSSLicenseCompliance::V0::GetAlertResponse)
      end
      def expire_alert_dismissal(repository_id:, number:, expiry_timestamp:)
        rpc_request = {
          repository_id: repository_id,
          number: number,
          expiry_timestamp: expiry_timestamp
        }
        rpc(:ExpireAlertDismissal, rpc_request)
      end

      sig do
        params(
          dismissals: T::Array[T::Hash[Symbol, T.untyped]]
        ).returns(OSSLicenseCompliance::V0::ExpireAlertDismissalByBatchResponse)
      end
      def expire_alert_dismissal_by_batch(dismissals:)
        proto_dismissals = dismissals.map do |dismissal|
          OSSLicenseCompliance::V0::ExpiredAlertDismissal.new(
            repository_id: dismissal[:repository_id],
            alert_number: dismissal[:alert_number],
            expiry_timestamp: dismissal[:expiry_timestamp]
          )
        end

        rpc_request = {
          dismissals: proto_dismissals
        }
        rpc(:ExpireAlertDismissalByBatch, rpc_request)
      end

      sig do
        params(
          repository_id: Integer,
          number: Integer
        ).returns(OSSLicenseCompliance::V0::CheckStatusResponse)
      end
      def check_status(repository_id:, number:)
        rpc_request = {
          repository_id: repository_id,
          pull_request_number: number
        }
        rpc(:CheckStatus, rpc_request)
      end

      sig do
        params(
          repository_id: Integer,
          number: Integer
        ).returns(OSSLicenseCompliance::V0::GetAlertsForPullRequestResponse)
      end
      def get_alerts_for_pull_request(repository_id:, number:)
        rpc_request = {
          repository_id: repository_id,
          pull_request_number: number
        }
        rpc(:GetAlertsForPullRequest, rpc_request)
      end

      sig do
        params(
          repository_id: Integer,
          number: Integer
        ).returns(OSSLicenseCompliance::V0::RestartCheckJobResponse)
      end
      def restart_check_job(repository_id:, number:)
        rpc_request = {
          repository_id: repository_id,
          pull_request_number: number
        }
        rpc(:RestartCheckJob, rpc_request)
      end

      # Add additional twirp method calls here with sig signature definitions
      #   - Input params should not reference Google::Protobuf classes. Simplify to core ruby types.
      #   - Output return type should be the OSSLicenseCompliance::V0:: Response class
      #
      # References:
      #   - https://github.com/github/osslicensecompliance/tree/main/proto#policylicenses
      #   - rbi defined request signatures: sorbet/rbi/dsl/*_request.rbi

    end
  end
end
