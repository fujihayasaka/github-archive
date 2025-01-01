# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Reference
  autoload :Wrapper, "github/goomba/reference/wrapper"
  autoload :Helpers, "github/goomba/reference/helpers"

  autoload :ReferenceFilter, "github/goomba/reference/reference_filter"
  autoload :UserFilter, "github/goomba/reference/user_filter"
  autoload :CurrentViewerFilter, "github/goomba/reference/current_viewer_filter"
  autoload :RepositoryResourceFilter, "github/goomba/reference/repository_resource_filter"
  autoload :RepositoryFilter, "github/goomba/reference/repository_filter"
  autoload :OrganizationResourceFilter, "github/goomba/reference/organization_resource_filter"
  autoload :AssetUrlRewriters, "github/goomba/reference/asset_url_rewriters"
  autoload :SecuredAssetFilter, "github/goomba/reference/secured_asset_filter"
  autoload :UploadContainerResourceFilter, "github/goomba/reference/upload_container_resource_filter"
  autoload :MemexSecuredAssetFilter, "github/goomba/reference/memex_secured_asset_filter"
  autoload :SavedReplySecuredAssetFilter, "github/goomba/reference/saved_reply_secured_asset_filter"
  autoload :GistSecuredAssetFilter, "github/goomba/reference/gist_secured_asset_filter"
  autoload :GHESSecuredLegacyAssetFilter, "github/goomba/reference/ghes_secured_legacy_asset_filter"

  AUTHORIZED_ELEMENT = "gh:authorized"
  UNAUTHORIZED_ELEMENT = "gh:unauthorized"

  class StaleReferenceError < StandardError; end

  # Create a cache key from a digest of the reference code that is used pre-cache
  CACHE_KEY = [Wrapper, Helpers]
    .filter_map { |constant| Object.const_source_location(constant.to_s).try(:[], 0) }
    .reduce(Digest::SHA256.new, :file)
    .hexdigest
    .freeze
end
