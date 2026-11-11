# typed: true
# frozen_string_literal: true

class AddOwnerIdIndexToAssetStatuses < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Assets)

  def change
    add_index :asset_statuses, :owner_id
  end
end
