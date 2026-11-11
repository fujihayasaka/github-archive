# typed: strict
# frozen_string_literal: true

class Api::Internal::MemcachedServerSync < Api::Internal
  include ReceiveSchemaWithOpenApi

  sig { returns(T::Boolean) }
  def externally_accessible?
    false
  end

  sig { returns(T::Boolean) }
  def require_request_hmac?
    # HMAC keys are stored in "GitHub.api_internal_memcached_server_sync_hmac_keys"
    # which reads "MEMCACHED_SERVER_SYNC_API_HMAC_SECRETS" environment variable
    true
  end

  sig { returns(T::Boolean) }
  def authenticated_for_private_mode?
    true
  end

  get "/internal/memcached-server-sync/servers/global/:site", operation_id: "memcached-server-sync/list-servers-global" do
    deliver_error! 400, message: "site parameter is required" if params[:site].blank?

    servers = []
    config = GitHub::Cache::Config.new.for_partition(:global, sites: [params[:site]])
    servers = config[:servers] if config[:servers]

    response = {
      servers: servers
    }
    deliver_raw response
  end
end
