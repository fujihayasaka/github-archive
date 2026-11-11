# typed: true

class DropDocusignWebhooks < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Ballast)

  def change
    drop_table :docusign_webhooks
  end
end
