# typed: true
# frozen_string_literal: true

# This class is a reference filter that handles references to upload container resources in HTML content.
# Subclasses of this class must override several methods that raise NotImplementedError in order to provide
# the necessary functionality for their specific resource types. These methods include:
#
# - asset_url_pattern
# - can_current_user_see_upload_container?
# - upload_container_type
#
# This class is designed to work specifically with the UserAsset model, as it is the only model that contains
# upload_container data. Attempting to use this class with other models may result in unexpected behavior.
module GitHub::Goomba::Reference
  class UploadContainerResourceFilter < ReferenceFilter
    ELEMENT = "gh:upload-container-resource-reference".freeze
    SELECTOR = Goomba::Selector.new(match: ELEMENT.gsub(":", "|"))

    # Only the UserAsset model has upload_container data
    ALLOWED_RESOURCE_TYPE = "UserAsset"

    # List of upload containers that can have assets associated with them prior to being created.
    UPLOAD_CONTAINERS_THAT_MAY_NOT_EXIST = [
      RepositoryAdvisorySecuredAssetFilter::CONTAINER,
    ]

    def selector
      SELECTOR
    end

    def call(node)
      asset = fetch_node_resource(node)
      return node.children.first if asset.nil?

      is_node_authorized = authorized_nodes.include?(node)

      if GitHub.storage_cluster_enabled?
        # Some upload containers such as gists, do not provide information about the viewer/current_user. In such cases,
        # we use the 'actor_id' from the context as a fallback to find the current viewer. For GHES installations where
        # the private mode is turned off, we fallback to the ghost user for calls made to public resources from logged
        # out users.
        current_actor = current_user || User.find_by(id: GitHub.context[:actor_id]) || User.ghost
        return AssetUrlRewriters::ClusterAssetUrlRewriter.new(
          current_actor,
          asset_url_pattern,
          context[:for_email],
          is_node_authorized
        ).call(node, asset)
      end

      AssetUrlRewriters::S3AssetUrlRewriter.new(
        asset_url_pattern,
        context[:for_email],
        is_node_authorized
      ).call(node, asset)
    end

    # Subclasses should override this method to return the asset URL pattern for the upload container type. The asset
    # URL pattern is used by the `GitHub::Goomba::Reference::AssetUrlRewriters::**` to determine who a given asset URL
    # should be rewritten.
    def asset_url_pattern
      raise NotImplementedError
    end

    # Subclasses should override this method to return a boolean indicating whether the current user has permission
    # to view a given upload container.
    def can_current_user_see_upload_container?(upload_container, current_user)
      raise NotImplementedError
    end

    def can_current_user_see_resource?(asset, current_user)
      asset.has_access?(current_user)
    end

    # Subclasses should override this method to return the upload container type.
    def upload_container_type
      raise NotImplementedError
    end

    # If the upload container is already preloaded in the context, it's recommended to override this method in the
    # subclass and return it. This can help avoid unnecessary database queries when rendering the HTML content.
    def preloaded_upload_container; end

    # Override the repository resource filter's stale check logic. User asset models won't regularly change, and this
    # filter doesn't need to check whether the rendered user asset content is stale or not.
    def async_check_for_stale_content(nodes)
      Promise.resolve
    end

    def preloaded_resources
      return @preloaded_resources if defined?(@preloaded_resources)

      @preloaded_resources = {}

      @preloaded_resources[upload_container_type] = {}
      if upload_container = preloaded_upload_container
        @preloaded_resources[upload_container_type][upload_container.id] = upload_container
      end

      @preloaded_resources
    end

    def async_load_resources(nodes)
      return Promise.resolve if nodes.empty?

      # batch load resources by type
      resource_loaders = nodes
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

      # batch load all resources' upload containers together, to minimize the number of org lookups needed
      Promise.all(resource_loaders)
        .then { |resource_type_lists| resource_type_lists.flatten }
        .then { |resources| async_load_resource_upload_containers(resources) }
    end

    def async_check_authorization(nodes)
      return Promise.resolve if nodes.empty?

      access_checks = nodes.map do |node|
        can_access_resource?(fetch_node_resource(node))
          .then { |accessible| authorized_nodes << node if accessible }
      end

      Promise.all(access_checks)
    end

    private

    def fetch_node_resource(node)
      node_resources[node]
    end

    def node_resources
      @node_resources ||= {}
    end

    def is_resource_type_allowed?(resource_type)
      resource_type == ALLOWED_RESOURCE_TYPE
    end

    # Returns a promise that resolves to all of the available resources for the resource type and
    # provided nodes.
    def async_batch_load_resource_type(resource_type, nodes)
      # If we can't perform an access check on the resource type, we should not attempt to load resources of that type.
      # We check for `Rails.env.development?` to provide immediate feedback to the developer on why a given resource
      # type is not loading.
      resource_allowed = is_resource_type_allowed?(resource_type)
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

    # Batch loads all needed upload container associations for the provided resources.
    # Returns nothing.
    def async_load_resource_upload_containers(resources)
      return if resources.empty?

      ids_to_load = Set.new
      resources.each do |r|
        next if r.association(:upload_container).loaded?

        # don't reload upload container which have already been loaded
        next if preloaded_resources[r.upload_container_type]&.has_key?(r.upload_container_id)

        # UserAssets may have a nil upload container id
        ids_to_load << r.upload_container_id if r.upload_container_id
      end

      return if ids_to_load.empty?

      Platform::Loaders::ActiveRecord.load_all(upload_container_type.constantize, ids_to_load.to_a)
        .then do |containers|
          containers.compact.each { |cont| preloaded_resources[upload_container_type][cont.id] ||= cont }

          resources.each do |r|
            next if r.association(:upload_container).loaded?
            r.upload_container = preloaded_resources[upload_container_type][r.upload_container_id]
          end
        end
    end

    def can_access_resource?(resource)
      return false if resource.nil?
      return false unless is_resource_type_allowed?(resource.class.name)

      if resource.uploader&.feature_enabled?(:secured_advisory_uploads)
        # For upload containers that may not exist yet, we need to fallback to the resource's access check.
        # Include the resource ID for caching purposes, but include `resource` in the identifier to avoid colliding
        # with the `upload_container_id` after it is created.
        upload_container_not_yet_created = !resource.upload_container_type.nil? && resource.upload_container_id.nil?
        if upload_container_not_yet_created && UPLOAD_CONTAINERS_THAT_MAY_NOT_EXIST.include?(resource.upload_container_type)
          upload_container_key = "#{resource.upload_container_type}/resource/#{resource.id}"
          @async_access_cache ||= {}
          if cached_access_check = @async_access_cache[upload_container_key]
            return cached_access_check
          end
          access_check = can_current_user_see_resource?(resource, current_user)
          return @async_access_cache[upload_container_key] = access_check
        end
      end

      # Not all UserAssets will have an upload container and we don't want to block the rendering of its content. This
      # is basically the case for UserAssets prior the introduction of upload containers.
      upload_container = resource.upload_container
      return true unless upload_container

      # cache the access check result per upload_containe
      upload_container_key = "#{upload_container.class.name}/#{upload_container.id}"
      @async_access_cache ||= {}
      if cached_access_check = @async_access_cache[upload_container_key]
        return cached_access_check
      end

      access_check = can_current_user_see_upload_container?(upload_container, current_user)
      @async_access_cache[upload_container_key] = access_check
    end
  end
end
