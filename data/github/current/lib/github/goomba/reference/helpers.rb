# typed: false
# frozen_string_literal: true

module GitHub::Goomba::Reference
  module Helpers
    # The following helpers return a String representing HTML that includes an authorization
    # element wrapping the HTML that will be shown to viewers in both authorized and unauthorized outcomes.
    # The authorization element will be processed by a node filter later in the pipeline execution to check
    # whether a current viewer has access to see the user mention.
    #
    # Helpers should be called from node filters with a block like the following.  In this case
    # def call(node)
    #   original_user_content = node.to_html
    #   tada_authorization_wrapper("my authorization value") do |wrapper|
    #     wrapper.authorized { "🎉 #{original_user_content}!" }
    #     wrapper.unauthorized { original_user_content }
    #   end
    # end

    # Returns a String wrapper for authorization that a viewer can see rich references to a user login
    def user_reference_wrapper(login, &block)
      wrapper = GitHub::Goomba::Reference::Wrapper.new(
        GitHub::Goomba::Reference::UserFilter::ELEMENT,
        { login: login }
      )

      block.call(wrapper)
      wrapper.to_s
    end

    # Returns a String wrapper for authorization that a viewer can see rich references to a project
    def project_reference_wrapper(project, &block)
      wrapper = GitHub::Goomba::Reference::Wrapper.new(
        GitHub::Goomba::Reference::ProjectFilter::ELEMENT,
        { project_id: project.id }
      )

      block.call(wrapper)
      wrapper.to_s
    end

    # Returns a String wrapper for running authorization checks on a viewer's user attributes
    def current_viewer_reference_wrapper(employee: false, &block)
      wrapper = GitHub::Goomba::Reference::Wrapper.new(
        GitHub::Goomba::Reference::CurrentViewerFilter::ELEMENT,
        { employee: employee }
      )

      block.call(wrapper)
      wrapper.to_s
    end

    # Returns a String wrapper for authorization that a viewer can see a resource in a repository,
    # and state to determine if content is stale
    def repository_resource_reference_wrapper(resource, check_type: :read, &block)
      wrapper = GitHub::Goomba::Reference::Wrapper.new(
        GitHub::Goomba::Reference::RepositoryResourceFilter::ELEMENT,
        {
          resource_type: resource.class.name,
          resource_id: resource.id,
          resource_signature: resource.updated_at,
          check_type: check_type.to_s,
        }
      )

      block.call(wrapper)
      wrapper.to_s
    end

    # Returns a String wrapper for authorization that a viewer can see a repository's contents
    def repository_reference_wrapper(repository, check_type: :visible, &block)
      wrapper = GitHub::Goomba::Reference::Wrapper.new(
        GitHub::Goomba::Reference::RepositoryFilter::ELEMENT,
        { repository_id: repository.id, check_type: check_type.to_s }
      )

      block.call(wrapper)
      wrapper.to_s
    end

    # Returns a String wrapper for authorization that a viewer can see an organization resource's contents
    def organization_resource_reference_wrapper(resource, &block)
      wrapper = GitHub::Goomba::Reference::Wrapper.new(
        GitHub::Goomba::Reference::OrganizationResourceFilter::ELEMENT,
        { resource_type: resource.class.name, resource_id: resource.id }
      )

      block.call(wrapper)
      wrapper.to_s
    end

    # Returns a String wrapper for authorization that a viewer can see a upload container resource's contents
    def upload_container_resource_reference_wrapper(resource, &block)
      wrapper = GitHub::Goomba::Reference::Wrapper.new(
        GitHub::Goomba::Reference::UploadContainerResourceFilter::ELEMENT,
        { resource_type: resource.class.name, resource_id: resource.id }
      )

      block.call(wrapper)
      wrapper.to_s
    end

    # Returns a String wrapper for authorization that a viewer can see private repository's UserAssets. This is used
    # in post cache `SecuredAssetFilter` reference filter to update UserAsset URLs for viewer authorized asset nodes
    # with JWT signed URLs so that private images and videos can be rendered.
    def secured_asset_reference_wrapper(asset, &block)
      asset_reference_wrapper(asset, GitHub::Goomba::Reference::SecuredAssetFilter::ELEMENT, &block)
    end

    # This is used in post cache `MemexSecuredAssetFilter` reference filter to update UserAsset URLs for viewer
    # authorized asset nodes with JWT signed URLs so that private images and videos can be rendered.
    def memex_secured_asset_reference_wrapper(asset, &block)
      asset_reference_wrapper(asset, GitHub::Goomba::Reference::MemexSecuredAssetFilter::ELEMENT, &block)
    end

    # This is used in post cache `GistSecuredAssetFilter` reference filter to update UserAsset URLs for viewer
    # authorized asset nodes with JWT signed URLs so that private images and videos can be rendered.
    def gist_secured_asset_reference_wrapper(asset, &block)
      asset_reference_wrapper(asset, GitHub::Goomba::Reference::GistSecuredAssetFilter::ELEMENT, &block)
    end

    def saved_reply_secured_asset_reference_wrapper(asset, &block)
      asset_reference_wrapper(asset, GitHub::Goomba::Reference::SavedReplySecuredAssetFilter::ELEMENT, &block)
    end

    def ghes_secured_legacy_asset_reference_wrapper(asset, &block)
      asset_reference_wrapper(asset, GitHub::Goomba::Reference::GHESSecuredLegacyAssetFilter::ELEMENT, &block)
    end

    def repository_advisory_secured_asset_reference_wrapper(asset, &block)
      asset_reference_wrapper(asset, GitHub::Goomba::Reference::RepositoryAdvisorySecuredAssetFilter::ELEMENT, &block)
    end

    # Returns a String wrapper for authorization that a viewer can see private UserAssets' repositories or upload_container.
    def asset_reference_wrapper(asset, element_name, &block)
      raise TypeError, "expected `asset` to be a `UserAsset`, but received #{asset.class}" unless asset.is_a?(UserAsset)

      attributes = { resource_type: UserAsset.name, resource_id: asset.id }

      content = block_given? ? yield.to_s : ""
      content = content.html_safe if result[:html_safe] # rubocop:disable Rails/OutputSafety
      ActionController::Base.helpers.content_tag(element_name, attributes) { content }
    end
  end
end
