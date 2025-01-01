# typed: true
# frozen_string_literal: true

# This is for proxima stamps to request dotcom to delete a
# MultiTenantProvisioningRequest record after tenant deprovisioning
# was successful
class Api::Internal::MultiTenantProvisioningRequests < Api::Internal
  sig { returns(T::Boolean) }
  def externally_accessible?
    true
  end

  sig { returns(T::Boolean) }
  def require_request_hmac?
    # HMAC key name is derived from the class name
    # Set in GitHub.api_internal_multi_tenant_provisioning_requests_hmac_keys
    # which reads "API_INTERNAL_MULTI_TENANT_PROVISIONING_REQUESTS_HMAC_KEYS"
    # environment variable
    true
  end

  get "/internal/multi_tenant_provisioning_requests/:region/:subdomain", operation_id: :internal do
    @route_owner = "@github/meao"
    subdomain = params[:subdomain]
    data_hosting_region = params[:region]
    deliver_error!(404) if !subdomain.present? || !data_hosting_region.present?

    record = MultiTenantProvisioningRequest.find_by(subdomain: subdomain, data_hosting_region: data_hosting_region)
    response = {
      subdomain: subdomain,
      data_hosting_region: data_hosting_region,
      record_found: record.present?,
    }

    if record.present?
      response[:industry] = record.industry
      response[:employees_size] = record.employees_size
      response[:marketing_consent] = record.marketing_consent
    end

    deliver_raw(response, status: 200)
  end

  delete "/internal/multi_tenant_provisioning_requests/:region/:subdomain", operation_id: :internal do
    @route_owner = "@github/meao"
    subdomain = params[:subdomain]
    data_hosting_region = params[:region]
    deliver_error!(404) if !subdomain.present? || !data_hosting_region.present?

    record = MultiTenantProvisioningRequest.find_by(subdomain: subdomain, data_hosting_region: data_hosting_region)
    response = {
      subdomain: subdomain,
      data_hosting_region: data_hosting_region,
      record_found: record.present?,
    }

    if record.present?
      record.destroy!
      response[:record_deleted] = true
    else
      response[:record_deleted] = false
    end

    deliver_raw(response, status: 200)
  end
end
