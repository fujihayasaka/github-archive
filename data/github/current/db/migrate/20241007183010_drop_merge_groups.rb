# typed: true

class DropMergeGroups < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    drop_table :merge_groups, if_exists: true
  end
end
