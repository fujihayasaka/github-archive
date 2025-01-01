# typed: true
# frozen_string_literal: true

### Based on lib/dependency_graph_platform/twirp/sbom_client.rb

# Extension of Sorbet generated files.  Methods were not part of the generated files.

module OSSLicenseCompliance
  module Twirp
    class OSSLicenseComplianceClient < OSSLicenseCompliance::Twirp::OSSLicenseComplianceConnection
      DEFAULT_READ_TIMEOUT = GitHub.default_request_timeout
      MESSAGE_PATH = "github.osscompliance_service.LicenseCompliance"

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
