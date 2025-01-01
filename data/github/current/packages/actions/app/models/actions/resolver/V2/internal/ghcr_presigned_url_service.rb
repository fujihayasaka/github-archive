# typed: true
# frozen_string_literal: true

# This class houses all logic related to generating a pre-signed GHCR URL to resolve Immutable actions.
class Actions::Resolver::V2::Internal::GhcrPresignedUrlService
  def initialize
    # No instance variables needed
  end

  # This method is responsible for generating a pre-signed URL that the runner can access.
  # It involves using the GHCR API client to generate the presigned URL and then transforming it to an endpoint in the monolith.
  def generate_presigned_urls(actor_id, actor_type, blob_identifiers)
    urls = ContainerRegistry::Twirp.container_registry_client.generate_presigned_urls(
      actor_id: actor_id,
      actor_type: actor_type,
      blob_identifiers: blob_identifiers
    )

    # Transform the pre-signed URLs to use the download archive API
    urls.map! do |url|
      transformed_url = transform_ghcr_presigned_url(url)
      transformed_url
    end
  end

  private

  # This is a helper method used to transform the GHCR pre-signed URL to a URL that directs to an API hosted by the monolith.
  # This allows for us to use the monolith as a pass-through for talking to GHCR.
  def transform_ghcr_presigned_url(url)
    uri = URI.parse(url)
    path_parts = T.must(uri.path).split("/")
    version_sha = path_parts.last
    action_owner = path_parts[2]
    action_name = path_parts[3]

    transformed_url = "#{GitHub.public_api_url}/internal/immutable-actions/#{action_owner}/#{action_name}/download/#{version_sha}?#{uri.query}"
    transformed_url
  end
end
