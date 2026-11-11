# typed: true
# frozen_string_literal: true

class AddBusinessToSoftDeletedOrganizations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :soft_deleted_organizations, bulk: true do |t|
      t.column :business_id, :bigint, unsigned: true, null: true
      t.index [:business_id], name: "index_soft_deleted_organizations_on_business_id"
    end
  end
end
