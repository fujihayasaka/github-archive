# typed: true

class AddLabelsUpdatedAtIndex < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :labels, bulk: true do |t|
      t.index :updated_at, name: "index_labels_on_updated_at"
      t.change :id, :bigint, unsigned: true
      t.change :repository_id, :bigint, unsigned: true
    end

    change_table :archived_labels, bulk: true do |t|
      t.index :updated_at, name: "index_labels_on_updated_at"
      t.change :id, :bigint, unsigned: true
      t.change :repository_id, :bigint, unsigned: true
    end
  end

  def down
    change_table :labels, bulk: true do |t|
      t.remove_index name: "index_labels_on_updated_at"
      t.change :id, :bigint
      t.change :repository_id, :int
    end

    change_table :archived_labels, bulk: true do |t|
      t.remove_index name: "index_labels_on_updated_at"
      t.change :id, :bigint
      t.change :repository_id, :int
    end
  end
end
