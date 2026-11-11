# typed: true
# frozen_string_literal: true

class Proxima::Api::ProvisioningRequestsClient < Proxima::Api
  def initialize(url: GitHub.api_internal_multi_tenant_provisioning_requests_url, hmac_key: GitHub.api_internal_multi_tenant_provisioning_requests_hmac_keys.first)
    super
  end
end
