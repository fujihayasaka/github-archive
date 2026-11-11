# typed: true
# frozen_string_literal: true

class Api::ExternalVulnerabilities < Api::App
  include ReceiveSchemaWithOpenApi

  MAX_VULNERABILITIES_PER_REQUEST = 100
  POLL_INTERVAL_SECONDS = 1

  # --- Enterprise sync ---

  post "/enterprises/:enterprise_id/external-vulnerabilities/sync", operation_id: "enterprise-admin/sync-enterprise-external-vulnerabilities", read_from_replicas: true do
    business = find_enterprise!
    innersource_owner = InnersourceVulnerabilityOwner.new(owner: business)

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(
      :"advisory-database-external-vulnerability-sync", innersource_owner.owner, default: false
    )

    control_access :write_enterprise_innersource_vulnerabilities,
      resource: innersource_owner.owner,
      allow_integrations: true,
      allow_user_via_granular_actor: false

    require_innersource_entitlement!(innersource_owner)

    parsed = parse_vulnerabilities!

    if async_enabled?(innersource_owner.owner)
      enqueue_sync!(owner: innersource_owner.owner, parsed: parsed, status_path_prefix: "/enterprises/#{business.slug}/external-vulnerabilities/sync/status")
    else
      with_write do
        service = ExternalVulnerabilitySync::SyncService.new(owner: innersource_owner.owner)
        result = service.perform(parsed)
        deliver_raw result.to_h
      end
    end
  end

  get "/enterprises/:enterprise_id/external-vulnerabilities/sync/status/:job_id", operation_id: "enterprise-admin/get-enterprise-external-vulnerability-sync-status", read_from_replicas: true do
    innersource_owner = InnersourceVulnerabilityOwner.new(owner: find_enterprise!)

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(
      :"advisory-database-external-vulnerability-sync", innersource_owner.owner, default: false
    )

    control_access :write_enterprise_innersource_vulnerabilities,
      resource: innersource_owner.owner,
      allow_integrations: true,
      allow_user_via_granular_actor: false

    require_innersource_entitlement!(innersource_owner)

    deliver_sync_status!(owner: innersource_owner.owner)
  end

  # --- Organization sync ---

  post "/organizations/:org_id/external-vulnerabilities/sync", operation_id: "security-advisories/sync-org-external-vulnerabilities", read_from_replicas: true do
    org = find_org!
    innersource_owner = InnersourceVulnerabilityOwner.new(owner: org)

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(
      :"advisory-database-external-vulnerability-sync", innersource_owner.owner, default: false
    )

    control_access :write_org_innersource_vulnerabilities,
      resource: innersource_owner.owner,
      allow_integrations: true,
      allow_user_via_granular_actor: false

    require_innersource_entitlement!(innersource_owner)

    parsed = parse_vulnerabilities!

    if async_enabled?(innersource_owner.owner)
      enqueue_sync!(owner: innersource_owner.owner, parsed: parsed, status_path_prefix: "/organizations/#{org.display_login}/external-vulnerabilities/sync/status")
    else
      with_write do
        service = ExternalVulnerabilitySync::SyncService.new(owner: innersource_owner.owner)
        result = service.perform(parsed)
        deliver_raw result.to_h
      end
    end
  end

  get "/organizations/:org_id/external-vulnerabilities/sync/status/:job_id", operation_id: "security-advisories/get-org-external-vulnerability-sync-status", read_from_replicas: true do
    innersource_owner = InnersourceVulnerabilityOwner.new(owner: find_org!)

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(
      :"advisory-database-external-vulnerability-sync", innersource_owner.owner, default: false
    )

    control_access :write_org_innersource_vulnerabilities,
      resource: innersource_owner.owner,
      allow_integrations: true,
      allow_user_via_granular_actor: false

    require_innersource_entitlement!(innersource_owner)

    deliver_sync_status!(owner: innersource_owner.owner)
  end

  private

  def async_enabled?(owner)
    FeatureFlag.vexi.enabled?(:external_vulnerability_sync_async, owner, default: false)
  end

  # Rejects the request with a 403 if the owner does not hold a GHAS Code Security entitlement
  # (Team or Enterprise plan with bundled GHAS or the unbundled Code Security split SKU; active
  # Code Security trials are honored).
  def require_innersource_entitlement!(innersource_owner)
    return if innersource_owner.entitled?
    deliver_error! 403, message: "Innersource advisories require a GitHub Advanced Security – Code Security license."
  end

  def parse_vulnerabilities!
    body = receive_with_openapi(expected_type: Array)

    if body.empty?
      deliver_error! 422, message: "Request body must be a non-empty array"
    end

    if body.size > MAX_VULNERABILITIES_PER_REQUEST
      deliver_error! 422, message: "Request body must contain at most #{MAX_VULNERABILITIES_PER_REQUEST} vulnerabilities"
    end

    parser = ExternalVulnerabilitySync::OSVParser.new
    parser.parse_all(body)
  rescue ExternalVulnerabilitySync::OSVParser::ValidationError => e
    deliver_error! 422, message: e.message
  rescue ExternalVulnerabilitySync::OSVParser::ParseError => e
    deliver_error! 422, message: e.message
  end

  def enqueue_sync!(owner:, parsed:, status_path_prefix:)
    job_status = ExternalVulnerabilitySync::JobStatus.create_for_sync(owner: owner)
    job_status.queued!

    # NOTE: Aqueduct has a ~5MB job data size limit. The current batch limit of
    # MAX_VULNERABILITIES_PER_REQUEST (100) plus client-side payload condensation
    # keeps serialized data well under this threshold. If the batch size limit
    # increases, consider using blob storage for large payloads.
    ExternalVulnerabilitySync::SyncJob.perform_later(
      job_status_id: job_status.id,
      owner: owner,
      vulnerabilities_data: parsed,
    )

    status_url = api_url("#{status_path_prefix}/#{job_status.id}")

    headers["Location"] = status_url
    headers["Retry-After"] = POLL_INTERVAL_SECONDS.to_s
    deliver_raw({ id: job_status.id, url: status_url, status: "queued" }, status: 202)
  end

  def deliver_sync_status!(owner:)
    job_status = ExternalVulnerabilitySync::JobStatus.find(params[:job_id])
    deliver_error! 404 unless job_status
    deliver_error! 404 unless job_status.owned_by?(owner)

    if !job_status.finished?
      headers["Retry-After"] = POLL_INTERVAL_SECONDS.to_s
      deliver_raw({ id: job_status.id, status: "processing" }, status: 202)
    elsif !job_status.success?
      deliver_raw({ status: "error", error: job_status.error_message }, status: 200)
    elsif job_status.sync_result
      deliver_raw job_status.sync_result
    else
      deliver_raw({ status: "error", error: "Sync completed but results are unavailable" }, status: 200)
    end
  end
end
