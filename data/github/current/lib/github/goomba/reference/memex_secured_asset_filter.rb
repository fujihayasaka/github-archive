# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Reference
  # MemexSecuredAssetFilter matches <gh:memex-secured-asset-reference> elements. It performs authorization
  # checks on ActiveRecord objects which require a `upload_container` association to be loaded.
  class MemexSecuredAssetFilter < UploadContainerResourceFilter
    ELEMENT = "gh:memex-secured-asset-reference".freeze
    SELECTOR = Goomba::Selector.new(match: ELEMENT.gsub(":", "|"))

    CONTAINER = "MemexProject"

    # matches a canonical asset URL e.g "/<users|orgs>/<user|org display_name>/projects/<id>/assets/<user_id>"
    ASSET_URL_PATTERN = %r{\/(users|orgs)+\/[^\/]+\/projects\/\d+\/assets\/(?<user_id>\d+)\/}

    def selector
      SELECTOR
    end

    def asset_url_pattern
      ASSET_URL_PATTERN
    end

    def can_current_user_see_upload_container?(upload_container, current_user)
      upload_container.viewer_can_read?(current_user)
    end

    def preloaded_upload_container
      context[:memex_project]
    end

    def upload_container_type
      CONTAINER
    end
  end
end
