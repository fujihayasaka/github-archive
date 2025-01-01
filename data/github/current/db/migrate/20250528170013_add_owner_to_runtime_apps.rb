# typed: true
# frozen_string_literal: true

class AddOwnerToRuntimeApps < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :runtime_apps, bulk: true do |t|
      t.bigint :owner_id, unsigned: true, null: true, comment: "User/Org ID of this Spark owner"
      t.bigint :organization_id, unsigned: true, null: true, comment: "Organization if the Spark is org owned"
    end
  end
end
