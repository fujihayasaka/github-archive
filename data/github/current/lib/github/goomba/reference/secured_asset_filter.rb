# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Reference
  # SecuredAssetFilter matches <gh:secured-asset-reference> elements. It generates a JWT token which contains a presigned s3 url to the end
  # end of an asset's `src` attribute. Additionally it adds a `data-canonical-src` attribute to the node for video tags.
  #
  # This filter is subclassed from RepositoryResourceFilter to make use of the common resource loading mechanism
  # from that filter.
  #
  # To use this authorization check in non-authorization HTML Pipeline filters, include GitHub::Goomba::Reference::Helpers
  # into a filter and call secured_asset_reference_wrapper.  See GitHub::Goomba::Async::SecureAssetsPresignFilter
  # for example usage
  class SecuredAssetFilter < RepositoryResourceFilter
    ELEMENT = "gh:secured-asset-reference".freeze
    SELECTOR = Goomba::Selector.new(match: ELEMENT.gsub(":", "|"))

    # matches a canonical asset URL e.g /<org>/<repo>/assets/<user_id>/
    ASSET_URL_PATTERN = %r{[^/]\/(?<owner_name>[\w.-]+)\/(?<repo_name>[\w.-]+)\/assets\/(?<user_id>\d+)\/}

    def selector
      SELECTOR
    end

    def call(node)
      asset = fetch_node_resource(node)
      return node.children.first if asset.nil?

      is_node_authorized = authorized_nodes.include?(node)

      if GitHub.storage_cluster_enabled?
        # Wiki pages do not provide information about the viewer/current_user. In such cases, we use the 'actor_id'
        # from the context as a fallback to find the current viewer. For GHES installations where the private mode is
        # turned off, we fallback to the ghost user for calls made to public resources from logged out users.
        current_actor = current_user || User.find_by(id: GitHub.context[:actor_id]) || User.ghost
        return AssetUrlRewriters::ClusterAssetUrlRewriter.new(
          current_actor,
          ASSET_URL_PATTERN,
          context[:for_email],
          is_node_authorized
        ).call(node, asset)
      end

      AssetUrlRewriters::S3AssetUrlRewriter.new(
        ASSET_URL_PATTERN,
        context[:for_email],
        is_node_authorized
      ).call(node, asset)
    end

    # Override the repository resource filter's stale check logic.  User asset models
    # won't regularly change, and this filter doesn't need to check whether
    # the rendered user asset content is stale or not.
    def async_check_for_stale_content(nodes)
      Promise.resolve
    end

    private

    def fetch_node_resource(node)
      node_resources[node]
    end
  end
end
