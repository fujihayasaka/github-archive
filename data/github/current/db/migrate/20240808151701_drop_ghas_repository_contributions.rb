class DropGhasRepositoryContributions < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    drop_table :ghas_repository_contributions do |t|
      t.bigint :repository_id, null: false
      t.bigint :user_id, null: false
      t.date :pushed_date, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.bigint :owner_id
      t.boolean :advanced_security_enabled, null: false
    end
  end
end
