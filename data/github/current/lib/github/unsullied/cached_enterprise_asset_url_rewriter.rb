# typed: strict
# frozen_string_literal: true

# This file is owned by the @github/object-storage team
#
# In GHES, we use signed tokens containing user information to verify access to user assets. Since Wikis are cached,
# the token of the user who last created or viewed the page before cache expiration would be cached. To prevent all
# users from accessing user assets via a single user's token, while still utilizing the cached version of a page,
# we inject the current user's token into the user asset URLs.
module GitHub::Unsullied
  class CachedEnterpriseAssetUrlRewriter < CachedAssetUrlRewriter
    extend T::Sig

    sig { params(cached: Page::DataHtml, current_user: T.nilable(User)).returns(Page::DataHtml) }
    def self.rewrite(cached, current_user)
      new(cached, current_user).rewrite
    end

    sig { params(cached: Page::DataHtml, current_user: T.nilable(User)).void }
    def initialize(cached, current_user)
      super(cached)
      @current_user = current_user
    end

    sig { params(asset: UserAsset).returns(String) }
    def rewrite_url_asset(asset)
      GitHub::Goomba::Reference::AssetUrlRewriters::ClusterAssetUrlRewriter.rewrite_for(@current_user, asset)
    end

    sig { returns(Regexp) }
    def regex_pattern
      /\/user\/(?<uid>\d+)\/files\/(?<guid>#{GitHub::Goomba::Async::AssetLoaders::AssetLoader::GUID_REGEX})/
    end

    sig { returns(Page::DataHtml) }
    def rewrite
      return @cached unless @current_user
      super
    end
  end
end
