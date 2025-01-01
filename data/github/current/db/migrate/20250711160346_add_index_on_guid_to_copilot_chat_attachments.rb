# typed: true
# frozen_string_literal: true

class AddIndexOnGuidToCopilotChatAttachments < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    add_index(:copilot_chat_attachments, :guid)
  end
end
