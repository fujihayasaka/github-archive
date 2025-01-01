# typed: true

class DropDocusignEnvelopes < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    drop_table :docusign_envelopes
  end
end
