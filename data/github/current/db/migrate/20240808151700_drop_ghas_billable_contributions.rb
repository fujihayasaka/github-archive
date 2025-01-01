class DropGhasBillableContributions < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    drop_table :ghas_billable_contributions do |t|
      t.bigint :billable_owner_id, null: false
      t.bigint :user_id, null: false
      t.date :latest_pushed_date, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.string :billable_owner_type, default: "Business"
    end
  end
end
