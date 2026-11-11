class DropIssueBoostAwards < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    drop_table :issue_boost_awards, if_exists: true
  end

  def down
    create_table :issue_boost_awards do |t|
      t.bigint :issue_boost_id, unsigned: true, null: false, index: true
      t.bigint :pull_request_id, unsigned: true, null: false, index: true
      t.bigint :user_id, unsigned: true, null: false, index: true
      t.integer :value, limit: 1, null: false, default: 1
      t.timestamps
    end
  end
end
