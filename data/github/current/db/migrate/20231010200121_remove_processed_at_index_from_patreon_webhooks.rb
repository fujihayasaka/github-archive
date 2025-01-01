# typed: true

class RemoveProcessedAtIndexFromPatreonWebhooks < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersBallast)

  def change
    change_table :patreon_webhooks, bulk: true do |t|
      t.remove_index name: :index_patreon_webhooks_on_processed_at, column: :processed_at
    end
  end
end
