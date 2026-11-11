# typed: true
# frozen_string_literal: true

class AddIndexToMarketplaceOrderPreviewsOnAccountId < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    change_table :marketplace_order_previews, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :user_id, :bigint, unsigned: true
      t.change :account_id, :bigint, unsigned: true
      t.change :marketplace_listing_id, :bigint, unsigned: true
      t.change :marketplace_listing_plan_id, :bigint, unsigned: true
      t.index :account_id
    end
  end
end
