# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Reference::AssetUrlRewriters
  class S3AssetUrlRewriter < AssetUrlRewriter
    # This is the secret key name to lookup for verification in Fastly
    FASTLY_DICTIONARY_KEY_NAME = "key5"

    def self.rewrite_for(asset)
      new("", false, true).rewrite_url(asset)
    end

    def call(node, asset)
      return node.children.first if GitHub.private_user_images_cdn_url.nil? && !GitHub.multi_tenant_enterprise?
      super(node, asset)
    end

    def rewrite_url(asset)
      return construct_presigned_url(asset) unless private_cdn_enabled?

      # Set up presigned URL uri using the private user images CDN as the starting point
      presigned_uri = Addressable::URI.parse(GitHub.private_user_images_cdn_url)

      # Replace the path with extracted path
      presigned_uri.path = asset.storage_s3_key(policy = nil)

      construct_presigned_url_jwt(asset, presigned_uri)
    end

    private

    def private_cdn_enabled?
      # Currently we should never use a CDN in Proxima. Re-visit if we decide to add CDN support
      !GitHub.multi_tenant_enterprise? && GitHub.private_image_upload_cdn_enabled?
    end

    def construct_presigned_url(asset)
      asset.storage_policy.download_url(expiration: DEFAULT_IMAGE_EXPIRATION_TIME.to_i)
    end

    def construct_presigned_url_jwt(asset, extracted_uri)
      presigned_s3_url = construct_presigned_url(asset)
      s3_uri  = Addressable::URI.parse(presigned_s3_url)

      jwt = JWT.encode(build_payload(s3_uri.path + "?" + s3_uri.query.to_s), GitHub.private_user_images_cdn_key, "HS256", { typ: "JWT" })

      uri = extracted_uri
      uri.query = ({ jwt: jwt }).to_query

      uri.to_s
    end

    def build_payload(path)
      {
        # The 'iss' and 'aud' values are used by code scanning to filter the private assets JWT out from its results.
        # If these values need to be changed, please make sure to align it with the code scanning team. Also, 'iss'
        # and 'aud' MUST be in this order and at beginning of the payload, so a pattern can be maintained during the
        # encoding.
        iss: "github.com",
        aud: "raw.githubusercontent.com",
        key: FASTLY_DICTIONARY_KEY_NAME,
        exp: DEFAULT_IMAGE_EXPIRATION_TIME.from_now.to_i,
        nbf: Time.now.to_i,
        path: path
      }
    end
  end
end
