# typed: true

class DropPendingTradeControlsRestrictions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    drop_table :pending_trade_controls_restrictions
  end
end
