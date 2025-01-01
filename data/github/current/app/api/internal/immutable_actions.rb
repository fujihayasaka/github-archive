# typed: true
# frozen_string_literal: true

class Api::Internal::ImmutableActions < Api::Internal
  def externally_accessible?
    true
  end

  def require_request_hmac?
    false
  end

  def authenticated_for_private_mode?
    true
  end

  # Redirects to blob storage or serves contents directly via a pre-signed url from GHCR to download an immutable action archive
  # Used in the actions resolution process for immutable actions, called by the runner. For more context see: https://github.com/github/package-registry-team/issues/8265
  get "/internal/immutable-actions/:action_owner/:action_name/download/:version_sha", skip_rate_limit: true, operation_id: :internal do
    action_owner = params[:action_owner]
    action_name = params[:action_name]
    version_sha = params[:version_sha]

    ghcr_presigned_url = recreate_ghcr_presigned_url(action_owner, action_name, version_sha, request.query_string)

    begin
      response = Net::HTTP.get_response(URI.parse(ghcr_presigned_url))
    rescue => e
      GitHub.logger.error("Failed to connect to GHCR presigned url", "error" => e.message, "gh.api.ghcr_presigned_url" => ghcr_presigned_url)
      deliver_error! 500, message: "The GitHub container registry is currently unavailable. Please try again later."
    end

    # do not print the response body in the case of serving contents directly
    if response.is_a?(Net::HTTPSuccess)
      GitHub.logger.info("Response from GHCR presigned url", "gh.api.ghcr_response.code" => response.code, "gh.api.ghcr_presigned_url" => ghcr_presigned_url)
    else
      GitHub.logger.info("Response from GHCR presigned url", "gh.api.ghcr_response.code" => response.code, "gh.api.ghcr_response.body" => response.body, "gh.api.ghcr_presigned_url" => ghcr_presigned_url)
    end

    if response.code == "307"
      # Perform the redirect by following the location header provided by GHCR
      redirect_url = response["location"]
      redirect redirect_url, 307
    # GHCR may return a 200 with the contents of the archive, deciding to serve it directly vs. using a redirect in certain cases.
    # One example is when the redirect fails, or for certain internal API calls as seen in the container-registry code here: https://github.com/github/container-registry/blob/1420a69800af728ae52c443ff5b08899e4fce44e/api/blobs.go#L123-L125
    elsif response.is_a?(Net::HTTPSuccess)
      content_type = response["content-type"]
      body = response.body

      content_type content_type
      body body
    elsif response.code == "401"
      deliver_error! 401, message: "Presigned URL is not valid"
    else
      deliver_error! 500
    end
  end

  private

  def recreate_ghcr_presigned_url(action_owner, action_name, version_sha, query_params)
    # We need to hardcode ghcr.io as the hostname because the environment variable in production is set to the internal GHCR URL.
    # This is a special case where we need to branch on environment, but if we need to use the external GHCR url again in the future, we should create a new environment variable.
    if Rails.env.production? && !GitHub.single_or_multi_tenant_enterprise? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      transformed_url = "https://ghcr.io/v2/#{action_owner}/#{action_name}/blobs/#{version_sha}"
    # We also need to hardcode in the container registry URL for multi-tenant enterprises because the environment variable is set to the service mesh URL.
    elsif GitHub.multi_tenant_enterprise?
      current_tenant = GitHub::CurrentTenant.get
      transformed_url = "https://containers.#{current_tenant.slug}.ghe.com/v2/#{action_owner}/#{action_name}/blobs/#{version_sha}"
    else
      transformed_url = "#{GitHub.container_registry_url}/v2/#{action_owner}/#{action_name}/blobs/#{version_sha}"
    end
    transformed_url + "?" + query_params
  end
end
