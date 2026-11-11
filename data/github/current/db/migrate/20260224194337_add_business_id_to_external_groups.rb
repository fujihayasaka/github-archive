# typed: true
# frozen_string_literal: true

class AddBusinessIdToExternalGroups < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :external_groups, bulk: true do |t|
      t.column :business_id, :bigint, unsigned: true, null: true
      t.index :business_id, name: "index_external_groups_on_business_id"
    end
  end
end
