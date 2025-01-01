# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Reference::AssetUrlRewriters
  autoload :AssetUrlRewriter, "github/goomba/reference/asset_url_rewriters/asset_url_rewriter"
  autoload :S3AssetUrlRewriter, "github/goomba/reference/asset_url_rewriters/s3_asset_url_rewriter"
  autoload :ClusterAssetUrlRewriter, "github/goomba/reference/asset_url_rewriters/cluster_asset_url_rewriter"
end
