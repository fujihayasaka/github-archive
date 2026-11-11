# typed: true
# frozen_string_literal: true

class DropModelsAttachments < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::GitHubModels)

  def change
    drop_table :models_attachments, if_exists: true
  end
end
