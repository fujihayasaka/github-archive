# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class UserAttachment < Platform::Unions::Base
      description "Types that may be an attachment uploaded by an user."

      visibility :internal, environments: [:dotcom]

      possible_types(
        Objects::UserAsset,
        Objects::RepositoryFile,
        Objects::CopilotChatAttachment,
      )
    end
  end
end
