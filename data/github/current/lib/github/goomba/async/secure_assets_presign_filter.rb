# typed: true
# frozen_string_literal: true

require_relative "asset_loaders"

module GitHub::Goomba::Async
  class SecureAssetsPreSignFilter < NodeFilter
    include GitHub::Goomba::Reference::Helpers

    class GistRelatedContextValidator
      def self.is_related_context?(context)
        (context[:blob].is_a?(TreeEntry) && context[:blob].repository.is_a?(Gist)) ||
        context[:entity].is_a?(Gist) ||
        context[:gist].is_a?(Gist) ||
        context[:subject].is_a?(GistComment)
      end
    end

    def self.feature_flags
      [:secure_user_assets_auth_check]
    end

    def self.enabled?(context)
      return true if GitHub.multi_tenant_enterprise? || GitHub.storage_cluster_enabled?

      if context[:entity].is_a?(GitHub::Unsullied::Wiki)
        # If the context is a wiki, we need to check the owner of the wiki's repo
        # to see if the feature flag is enabled
        owner = context[:entity].repository.owner
        return GitHub.flipper[:secure_user_assets_auth_check].enabled?(owner)
      end

      if context[:memex_project]&.is_a?(MemexProject)
        owner = context[:memex_project].owner
        return GitHub.flipper[:secure_user_assets_auth_check].enabled?(owner)
      end

      return true if GistRelatedContextValidator.is_related_context?(context)

      # User assets in saved replies have the their `uploader_container` set to owner
      if context[:subject]&.is_a?(SavedReply)
        # If the context subject is a SavedReply, we need to check the owner to see if the feature flag is enabled
        owner = context[:subject].user
        return GitHub.flipper[:secure_user_assets_auth_check].enabled?(owner)
      end

      # During saved reply creation, we will not have a subject, so we need to subject type
      if context[:subject_type] == SavedReply.name
        # During saved reply creation, we need to check current user has the feature flag enabled since they will
        # be the owner of the saved reply
        user = context[:current_user]
        return GitHub.flipper[:secure_user_assets_auth_check].enabled?(user)
      end

      return false unless context[:entity].is_a?(Repository)
      return false unless context[:entity].respond_to?(:owner)
      GitHub.flipper[:secure_user_assets_auth_check].enabled?(context[:entity].owner)
    end

    def selector
      @selector
    end

    def initialize(*args)
      super
      @node_src_assets = {}

      # Should match any image where:
      #   src="https://github.com/org/repo/assets/<user_id>/<guid>"
      #   src="https://github.com/user|org/<username>/projects/<project_id>/assets/<user_id>/<guid>"
      #   src="https://gist.github.com/assets/<user_id/<guid>"
      @selector = Goomba::Selector.new(match: "img[src^='#{GitHub.url}'][src*='assets'],img[src^='#{GitHub.gist_url}'][src*='assets']")
    end

    def async_scan
      loader_instances = assset_loader

      loaders = @nodes.map do |node|
        loader_instances.map do |loader_instance|
          loader_instance.load_node_asset(node)
        end
      end.flatten.compact

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

      return node unless check_asset_authorization?(asset)

      is_inside_link = find_node_ancestor(node, "a").present?
      # Used by ImageMaxWidthFilter to avoid wrapping in another link
      node["secured-asset-link"] = "" if is_inside_link

      return saved_reply_secured_asset_reference_wrapper(asset) { node } if asset.upload_container_type == User.name
      return memex_secured_asset_reference_wrapper(asset) { node } if is_memex_project?
      return gist_secured_asset_reference_wrapper(asset) { node } if GistRelatedContextValidator.is_related_context?(context)
      if asset.uploader&.feature_enabled?(:secured_advisory_uploads)
        return repository_advisory_secured_asset_reference_wrapper(asset) { node } if asset.upload_container_type == RepositoryAdvisory.name
      end

      secured_asset_reference_wrapper(asset) { node }
    end

    private

    def check_asset_authorization?(asset)
      asset.repository_id.present? || asset.upload_container
    end

    def is_repository_or_related?
      context[:entity].is_a?(Repository) || context[:entity].is_a?(GitHub::Unsullied::Wiki)
    end

    def is_saved_reply?
      context[:subject_type] == SavedReply.name
    end

    def is_memex_project?
      context[:memex_project]&.is_a?(MemexProject)
    end

    def assset_loader
      return [GitHub::Goomba::Async::AssetLoaders::SavedReplyAssetLoader.new(context[:current_user]),
      GitHub::Goomba::Async::AssetLoaders::RepositoryAssetLoader.new(context[:entity], context[:current_user])] if is_repository_or_related?
      return [GitHub::Goomba::Async::AssetLoaders::SavedReplyAssetLoader.new(context[:current_user]),
      GitHub::Goomba::Async::AssetLoaders::MemexAssetLoader.new(context[:memex_project], context[:current_user])] if is_memex_project?
      return [GitHub::Goomba::Async::AssetLoaders::GistAssetLoader.new(context[:current_user])] if GistRelatedContextValidator.is_related_context?(context)
      return [GitHub::Goomba::Async::AssetLoaders::SavedReplyAssetLoader.new(context[:current_user])] if is_saved_reply?

      [GitHub::Goomba::Async::AssetLoaders::AssetLoader.new(context[:current_user])]
    end
  end
end
