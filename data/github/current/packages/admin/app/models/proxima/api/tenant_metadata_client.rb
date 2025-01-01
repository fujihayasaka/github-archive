# typed: true
# frozen_string_literal: true

class Proxima::Api::TenantMetadataClient < Proxima::Api
  def initialize(url: GitHub.proxima_tenant_metadata_url, hmac_key: GitHub.proxima_tenant_metadata_hmac_key, connection_timeout: 10)
    super
  end
end
