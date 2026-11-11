# typed: true
# frozen_string_literal: true

class Stafftools::LicenseComplianceController < StafftoolsController
  layout "layouts/stafftools/repository/overview"

  before_action :ensure_org_not_user
  before_action :ensure_repo_exists

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
    only: [:index]

  DEFAULT_DISTRIBUTED_POLICY_NAME = "distributed"

  def self.react_bundle_name
    "stafftools-license-compliance"
  end

  def index
    repo = current_repository
    license_compliance_on = FeatureFlag.vexi.enabled?(:dependency_graph_license_compliance, repo, repo.owner, repo.business, default: false)
    payload = {
      licenseComplianceOn: license_compliance_on,
      repositoryNameWithOwner: repo.name_with_owner,
      repositoryPolicy: license_compliance_on ? fetch_repository_policy(repo) : empty_policy
    }
    respond_with_react(
      payload: LicenseComplianceRoutePayload.new(payload),
      title: "LicenseCompliance"
    )
  end

  class LicenseComplianceRoutePayload < ReactPayload::Base
    def route_id
      "licenseComplianceRoute"
    end

    def initialize(payload)
      @payload = payload
    end

    def payload
      @payload
    end
  end

  private

  sig { returns(OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient) }
  memoize def license_compliance_client
    OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient.new
  end

  sig { params(repo: Repository).returns(Hash) }
  def fetch_repository_policy(repo)
    response = license_compliance_client.get_combined_repository_policy(
      distribution_policy_name: DEFAULT_DISTRIBUTED_POLICY_NAME,
      repository_id: repo.id,
      organization_id: repo.owner&.id,
      enterprise_id: repo.business_id
    )
    serialize_policy(response.policy)
  rescue OSSLicenseCompliance::Twirp::BaseError => e
    empty_policy.merge(error: e.message)
  end

  sig { params(policy: T.nilable(OSSLicenseCompliance::V0::CombinedRepositoryPolicy)).returns(Hash) }
  def serialize_policy(policy)
    return empty_policy if policy.nil?

    {
      allowedLicenses: policy.licenses.map { |license| serialize_license(license) },
      packageExceptions: policy.packages.map { |package| serialize_package(package) },
      customRemediationGuidance: policy.custom_remediation_guidance
    }
  end

  sig { returns(Hash) }
  def empty_policy
    {
      allowedLicenses: [],
      packageExceptions: [],
      customRemediationGuidance: ""
    }
  end

  # Enum mappings are kept as simple strings so stafftools changes are not needed when adding new enum values
  sig { params(license: OSSLicenseCompliance::V0::CombinedLicense).returns(Hash) }
  def serialize_license(license)
    {
      spdxId: license.spdx_id,
      addedAt: format_date(license.added_at),
      level: license.level.to_s.sub("POLICY_LEVEL_", "").downcase
    }
  end

  # Enum mappings are kept as simple strings so stafftools changes are not needed when adding new enum values
  sig { params(package: OSSLicenseCompliance::V0::CombinedPackage).returns(Hash) }
  def serialize_package(package)
    {
      packageManager: package.package_manager.to_s.sub("PACKAGE_MANAGER_", "").downcase,
      name: package.name,
      action: package.action.to_s.sub("PACKAGE_ACTION_", "").downcase,
      reason: package.reason,
      extraAllowedSpdxIds: package.extra_allowed_spdx_ids.to_a,
      addedAt: format_date(package.added_at),
      level: package.level.to_s.sub("POLICY_LEVEL_", "").downcase
    }
  end

  sig { params(timestamp: T.nilable(Google::Protobuf::Timestamp)).returns(String) }
  def format_date(timestamp)
    return "" if timestamp.nil?
    timestamp.to_time.strftime("%b %d, %Y %H:%M")
  end
end
