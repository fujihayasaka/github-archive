# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async::AssetLoaders
  autoload :AssetLoader, "github/goomba/async/asset_loaders/asset_loader"
  autoload :RepositoryAssetLoader, "github/goomba/async/asset_loaders/repository_asset_loader"
  autoload :MemexAssetLoader, "github/goomba/async/asset_loaders/memex_asset_loader"
  autoload :GistAssetLoader, "github/goomba/async/asset_loaders/gist_asset_loader"
  autoload :SavedReplyAssetLoader, "github/goomba/async/asset_loaders/saved_reply_asset_loader"
  autoload :GHESLegacyAssetLoader, "github/goomba/async/asset_loaders/ghes_legacy_asset_loader"
end
