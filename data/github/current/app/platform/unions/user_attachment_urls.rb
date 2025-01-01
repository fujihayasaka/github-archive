# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class UserAttachmentUrls < Platform::Unions::Base
      description "Types that may be an attachment uploaded by an user."

      visibility :internal, environments: [:dotcom]

      possible_types(
        Objects::CopilotChatAttachment,
      )
    end
  end
end
