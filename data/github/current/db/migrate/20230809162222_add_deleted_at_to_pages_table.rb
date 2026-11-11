# typed: true

class AddDeletedAtToPagesTable < ActiveRecord::Migration[7.1]

  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :pages, bulk: true do |t|
      t.datetime :deleted_at, precision: 6, null: true
      t.column :deleted_cname, "varchar(255)", null: true

      t.index :deleted_at
    end
  end
end
