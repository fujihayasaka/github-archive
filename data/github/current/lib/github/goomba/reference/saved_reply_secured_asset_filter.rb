# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Reference
  # SavedReplySecuredAssetFilter matches <gh:saved-reply-secured-asset-reference> elements. It performs authorization
  # checks on ActiveRecord objects which require a `upload_container` association to be loaded.
  class SavedReplySecuredAssetFilter < UploadContainerResourceFilter
    ELEMENT = "gh:saved-reply-secured-asset-reference".freeze
    SELECTOR = Goomba::Selector.new(match: ELEMENT.gsub(":", "|"))

    CONTAINER = "User"

    # matches a canonical asset URL e.g "/settings/replies/assets/<user_id>"
    ASSET_URL_PATTERN = %r{\/settings\/replies\/assets\/(?<user_id>\d+)\/}

    def selector
      SELECTOR
    end

    def asset_url_pattern
      ASSET_URL_PATTERN
    end

    def secured_asset?(asset)
      true
    end

    def can_current_user_see_upload_container?(upload_container, current_user)
      upload_container == current_user
    end

    def preloaded_upload_container
      context[:current_user]
    end

    def upload_container_type
      CONTAINER
    end
  end
end
