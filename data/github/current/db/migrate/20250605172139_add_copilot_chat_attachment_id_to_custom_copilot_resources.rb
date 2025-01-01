# typed: true
# frozen_string_literal: true

class AddCopilotChatAttachmentIdToCustomCopilotResources < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table(:custom_copilot_resources, bulk: true) do |t|
      t.column(:copilot_chat_attachment_id, :bigint, unsigned: true, null: true, after: :custom_copilot_id)
      t.index(:copilot_chat_attachment_id, unique: true)
    end
  end
end
