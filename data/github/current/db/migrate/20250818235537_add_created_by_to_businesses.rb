# typed: true

class AddCreatedByToBusinesses < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :businesses, bulk: true do |t|
      t.column :created_by_id, :bigint, null: true, unsigned: true, comment: "id of the actor who created the business"
      t.index :created_by_id
    end
  end
end
