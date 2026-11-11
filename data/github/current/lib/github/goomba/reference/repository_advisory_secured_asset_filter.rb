# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Reference
  class RepositoryAdvisorySecuredAssetFilter < UploadContainerResourceFilter
    ELEMENT = "gh:repository-advisory-secured-asset-reference".freeze
    SELECTOR = Goomba::Selector.new(match: ELEMENT.gsub(":", "|"))

    CONTAINER = "RepositoryAdvisory"

    # matches a canonical asset URL e.g "/user-attachments/assets/<guid>"
    ASSET_URL_PATTERN = %r{\/user-attachments\/assets\/[0-9a-fA-F\-]+(\/)?$}

    def selector
      SELECTOR
    end

    def asset_url_pattern
      ASSET_URL_PATTERN
    end

    def can_current_user_see_upload_container?(upload_container, current_user)
      upload_container.readable_by?(current_user)
    end

    def upload_container_type
      CONTAINER
    end
  end
end
