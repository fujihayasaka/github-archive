# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class UserAttachmentType < Platform::Enums::Base
      description "User attachment type."
      visibility :internal

      value "NON_MEDIA", "Non-media files uploaded by the user, i.e: repository files.", value: :non_media
      value "MEDIA", "Media(image and videos) files uploaded by the user, i.e: user assets.", value: :media
    end
  end
end
