# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Reference
  # GHESSecuredLegacyAssetFilter matches <gh:ghes-secured-legacy-asset-reference> elements. It will sign legacy assets
  # urls with an HMAC token.
  class GHESSecuredLegacyAssetFilter < ReferenceFilter
    ELEMENT = "gh:ghes-secured-legacy-asset-reference".freeze
    SELECTOR = Goomba::Selector.new(match: ELEMENT.gsub(":", "|"))

    # Only the UserAsset resource type is allowed to be loaded by this filter.
    ALLOWED_RESOURCE_TYPE = "UserAsset"

    def selector
      SELECTOR
    end

    # User asset models won't regularly change, and this filter doesn't need to check whether the rendered user asset
    # content is stale or not.
    def async_check_for_stale_content(nodes)
      Promise.resolve
    end

    # We won't perform authorization for legacy assets, as they don't carry data about their containers
    def async_check_authorization(nodes)
      Promise.resolve
    end

    def call(node)
      asset = node_resources[node]
      return node.children.first if asset.nil?

      AssetUrlRewriters::ClusterAssetUrlRewriter.new(
        current_actor,
        GitHub::Goomba::Async::AssetLoaders::GHESLegacyAssetLoader::ASSET_URL_PATTERN,
        context[:for_email],
        true
      ).call(node, asset)
    end

    def async_load_resources(nodes)
      return Promise.resolve if nodes.empty?

      # batch load resources by type
      resource_loaders = resource_loaders(nodes)

      # batch load all resources
      Promise.all(resource_loaders).then { |resource_type_lists| resource_type_lists.flatten }
    end

    private

    def node_resources
      @node_resources ||= {}
    end

    def current_actor
      # Some sections of the site, such as wikis, do not provide information about the viewer/current_user. In such
      # cases, we use the 'actor_id' from the context as a fallback to find the current viewer. For installations
      # where the private mode is turned off, we fallback to the ghost user for calls made to public resources from
      # logged out users.
      current_user || (GitHub.context[:actor_id] && User.find_by(id: GitHub.context[:actor_id])) || User.ghost
    end

    def resource_loaders(nodes)
      nodes
        .group_by { |node| node["resource_type"] }
        .map do |type, nodes|
          async_batch_load_resource_type(type, nodes).then do |resources|
            next [] if resources.empty?
            # populate a map linking node->resource for fast resource lookup
            # during authorization
            rscs = resources.compact
            populate_node_resource_map(nodes, rscs)
            rscs
          end
        end
    end

    # Returns a promise that resolves to all of the available resources for the resource type and
    # provided nodes.
    def async_batch_load_resource_type(resource_type, nodes)
      # If we can't perform an access check on the resource type, we should not attempt to load resources of that type.
      # We check for `Rails.env.development?` to provide immediate feedback to the developer on why a given resource
      # type is not loading.
      resource_allowed = resource_type == ALLOWED_RESOURCE_TYPE
      raise TypeError, "cannot load resources of type #{resource_type}" if !resource_allowed && Rails.env.development?
      return Promise.resolve([]) unless resource_allowed

      resources_ids = nodes.map { |node| node["resource_id"].to_i }
      resource_ids_to_load = Set.new(resources_ids)

      Platform::Loaders::ActiveRecord.load_all(resource_type.constantize, resource_ids_to_load.to_a)
    end

    # Populate the node_resource map which links a node to its corresponding resource for easy lookup
    # Returns nothing.
    def populate_node_resource_map(nodes, resources)
      indexed_resources = resources.index_by(&:id)
      nodes.each do |node|
        index = node["resource_id"].to_i
        resource = indexed_resources[index]
        next unless resource

        node_resources[node] = resource
      end
    end
  end
end
