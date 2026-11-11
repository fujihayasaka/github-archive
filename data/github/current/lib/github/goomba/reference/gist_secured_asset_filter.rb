# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Reference
  # GistSecuredAssetFilter matches <gh:gist-secured-asset-reference> elements. It performs authorization
  # checks on ActiveRecord objects which require a `upload_container` association to be loaded.
  class GistSecuredAssetFilter < UploadContainerResourceFilter
    ELEMENT = "gh:gist-secured-asset-reference".freeze
    SELECTOR = Goomba::Selector.new(match: ELEMENT.gsub(":", "|"))

    CONTAINER = "Gist"

    # matches a canonical asset URL e.g "/assets/<user_id>"
    ASSET_URL_PATTERN = %r{\/assets\/(?<user_id>\d+)\/}

    def selector
      SELECTOR
    end

    def asset_url_pattern
      ASSET_URL_PATTERN
    end

    def can_current_user_see_upload_container?(upload_container, current_user)
      # Gists are made private by concealing their URLs. Anyone who has the URL can view the gist, irrespective of
      # whether they are logged in or not.
      true
    end

    def upload_container_type
      CONTAINER
    end
  end
end
