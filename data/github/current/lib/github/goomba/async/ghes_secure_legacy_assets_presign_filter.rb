# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async
  class GHESSecureLegacyAssetsPresignFilter < NodeFilter
    include GitHub::Goomba::Reference::Helpers

    def self.enabled?(context)
      GitHub.storage_cluster_enabled?
    end

    def selector
      @selector
    end

    def initialize(*args)
      super
      @node_src_assets = {}

      # Should match any image where src="https://<ghes-url>/user/<user>/files/<guid>
      @selector = Goomba::Selector.new(match: "img[src^='#{GitHub.storage_cluster_url}'][src*='user'][src*='files'], img[src^='#{storage_cluster_url_isolated_subdomain_complement}'][src*='user'][src*='files']")
    end

    def async_scan
      loader_instance = assset_loader
      loaders = @nodes.map { |node| loader_instance.load_node_asset(node) }.compact

      # return a promise waiting on all asset loaders
      Promise.all(loaders).then do |res|
        # We want `nil` results to be ignored, so we compact the results before merging`
        compacted_res = res.compact
        next if compacted_res.empty?

        @node_src_assets.merge!(compacted_res.reduce({}, :merge))
      end
    end

    def call(node)
      # fetch the preloaded UserAsset data
      asset = @node_src_assets[node["src"]]
      return node unless asset.present?

      # Used by AnimatedImageFilter for checking content type
      node["content-type-secured-asset"] = asset.content_type

      is_inside_link = find_node_ancestor(node, "a").present?
      # Used by ImageMaxWidthFilter to avoid wrapping in another link
      node["secured-asset-link"] = "" if is_inside_link

      ghes_secured_legacy_asset_reference_wrapper(asset) { node }
    end

    # This is a helper method to generate the subdomain complement for the
    # storage cluster URL. It is used in the html pipelines to handle GHES file references
    # that were made with a previous, different isolated subdomain setting.
    def storage_cluster_url_isolated_subdomain_complement
      # If the storage cluster URL is nil, we shouldn't try to generate a complement
      if GitHub.storage_cluster_url.nil?
        ""
      elsif GitHub.subdomain_isolation?
        # If we are using isolated subdomains, we need to remove the subdomain from the URL and append 'storage' after the host
        GitHub.storage_cluster_url.sub(%r{(https?)://[^.]+\.(.+)}, '\1://\2') + "/storage"
      else
        # If we are not using isolated subdomains, we need to remove storage from the path and append the 'media' subdomain to the beginning of the host
        GitHub.storage_cluster_url.sub(%r{(https?://)([^/]+)/(storage)?/?(.*)}, '\1media.\2\4')
      end
    end

    private

    def assset_loader
      # Some sections of the site, such as wikis, do not provide information about the viewer/current_user. In such
      # cases, we use the 'actor_id' from the context as a fallback to find the current viewer. For installations
      # where the private mode is turned off, we fallback to the ghost user for calls made to public resources from
      # logged out users.
      current_actor = context[:current_user] || User.find_by(id: GitHub.context[:actor_id]) || User.ghost
      GitHub::Goomba::Async::AssetLoaders::GHESLegacyAssetLoader.new(current_actor)
    end
  end
end
