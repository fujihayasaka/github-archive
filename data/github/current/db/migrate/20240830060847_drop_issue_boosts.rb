class DropIssueBoosts < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    drop_table :issue_boosts, if_exists: true
  end

  def down
    create_table :issue_boosts do |t|
      t.integer :user_id, null: false, index: true
      t.integer :issue_id, null: false, index: { unique: true }
      t.integer :value, limit: 1, null: false
      t.timestamps
    end
  end
end
