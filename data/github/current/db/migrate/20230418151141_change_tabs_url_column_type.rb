# typed: true

class ChangeTabsUrlColumnType < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def up
    change_table :tabs, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, auto_increment: true
      t.change :repository_id, :bigint, unsigned: true, null: true
      t.change :url, :text
    end
  end

  def down
    change_column :tabs, :url, :string
  end
end
