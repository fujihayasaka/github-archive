# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class UserAttachmentUrlsType < Platform::Enums::Base
      description "User attachment urls type."
      visibility :internal

      value "COPILOT_CHAT_ATTACHMENT", "Media files uploaded by the user via Copilot chat.", value: :copilot_chat_attachment
    end
  end
end
