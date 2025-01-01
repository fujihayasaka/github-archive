# typed: strict
# frozen_string_literal: true

# This file is owned by the @github/object-storage team
#
# In Dotcom, we use a short lived JWT that gets sent to our private CDN in order to sign the S3 urls and, as wikis are
# cached, we need to make sure to refresh the said jwt every time we serve a cached wiki page, so users don't see broken
# links.
module GitHub::Unsullied
  class CachedDotcomAssetUrlRewriter < CachedAssetUrlRewriter
    extend T::Sig

    sig { params(cached: Page::DataHtml).returns(Page::DataHtml) }
    def self.rewrite(cached)
      new(cached).rewrite
    end

    sig { params(host: String).returns(T::Boolean) }
    def is_host_valid?(host)
      # In Proxima, we won't have legacy assets, so we can just return true
      return true if GitHub.multi_tenant_enterprise?

      # We want to make sure to only rewrite urls for the private CDN. Urls for the public CDN should left be intact.
      private_uri = Addressable::URI.parse(GitHub.private_user_images_cdn_url || "")
      host == private_uri.host
    end

    sig { params(asset: UserAsset).returns(String) }
    def rewrite_url_asset(asset)
      GitHub::Goomba::Reference::AssetUrlRewriters::S3AssetUrlRewriter.rewrite_for(asset)
    end

    # Example of urls:
    #
    # Dotcom:
    #   https://private-user-images.githubusercontent.com/<user_id>/<asset_id>-<guid>.<extension>
    #
    # Proxima:
    #   https://objects-origin.<tenant>.ghe.com/<bucket>/<user_id>/<asset_id>-<guid>.<extension>
    sig { returns(Regexp) }
    def regex_pattern
      /(?<uid>\d+)\/(?<aid>\d+)-(?<guid>#{GitHub::Goomba::Async::AssetLoaders::AssetLoader::GUID_REGEX})/
    end
  end
end
