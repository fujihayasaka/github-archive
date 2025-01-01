# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Reference::AssetUrlRewriters
  class ClusterAssetUrlRewriter < AssetUrlRewriter

    def self.rewrite_for(actor, asset)
      new(actor, "", false, true).rewrite_url(asset)
    end

    def initialize(actor, url_pattern, for_email, is_node_authorized)
      super(url_pattern, for_email, is_node_authorized)
      @actor = actor
    end

    def rewrite_url(asset)
      asset.storage_policy(actor: @actor).download_url(expiration: DEFAULT_IMAGE_EXPIRATION_TIME)
    end
  end
end
