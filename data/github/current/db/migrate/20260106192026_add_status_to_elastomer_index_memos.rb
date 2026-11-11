# typed: true

class AddStatusToElastomerIndexMemos < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Search)

  def up
    change_table :elastomer_index_memos, bulk: true do |t|
      t.change :id, :bigint, unsigned: true  # Not related to new column, but this was a lintable offense
      t.column :status, :string, limit: 16, null: false, default: "creating"
    end
  end

  def down
    remove_column :elastomer_index_memos, :status
  end
end
