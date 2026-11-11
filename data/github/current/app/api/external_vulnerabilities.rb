# typed: true
# frozen_string_literal: true

class Api::ExternalVulnerabilities < Api::App
  include ReceiveSchemaWithOpenApi

  MAX_VULNERABILITIES_PER_REQUEST = 100

  post "/enterprises/:enterprise_id/external-vulnerabilities/sync", operation_id: "enterprise-admin/sync-enterprise-external-vulnerabilities", read_from_replicas: true do
    business = find_enterprise!

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(
      :"advisory-database-external-vulnerability-sync", business, default: false
    )

    control_access :write_enterprise_innersource_vulnerabilities,
      resource: business,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    with_write do
      result = sync_vulnerabilities!(owner: business)
      deliver_raw result.to_h
    end
  end

  post "/organizations/:org_id/external-vulnerabilities/sync", operation_id: "security-advisories/sync-org-external-vulnerabilities", read_from_replicas: true do
    org = find_org!

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(
      :"advisory-database-external-vulnerability-sync", org, default: false
    )

    control_access :write_org_innersource_vulnerabilities,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    with_write do
      result = sync_vulnerabilities!(owner: org)
      deliver_raw result.to_h
    end
  end

  private

  def sync_vulnerabilities!(owner:)
    body = receive_with_openapi(expected_type: Array)

    if body.empty?
      deliver_error! 422, message: "Request body must be a non-empty array"
    end

    if body.size > MAX_VULNERABILITIES_PER_REQUEST
      deliver_error! 422, message: "Request body must contain at most #{MAX_VULNERABILITIES_PER_REQUEST} vulnerabilities"
    end

    parser = ExternalVulnerabilitySync::OSVParser.new
    parsed = parser.parse_all(body)

    service = ExternalVulnerabilitySync::SyncService.new(
      owner: owner,
    )

    service.perform(parsed)
  rescue ExternalVulnerabilitySync::OSVParser::ValidationError => e
    deliver_error! 422, message: e.message
  rescue ExternalVulnerabilitySync::OSVParser::ParseError => e
    deliver_error! 422, message: e.message
  end
end
