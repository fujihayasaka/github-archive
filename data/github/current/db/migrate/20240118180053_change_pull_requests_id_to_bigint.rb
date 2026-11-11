class ChangePullRequestsIdToBigint < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :pull_requests, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :repository_id, :bigint, unsigned: true, null: false
      t.change :user_id, :bigint, unsigned: true, default: nil
      t.change :base_repository_id, :bigint, unsigned: true, null: true
      t.change :head_repository_id, :bigint, unsigned: true, null: true
      t.change :base_user_id, :bigint, unsigned: true, null: true
      t.change :head_user_id, :bigint, unsigned: true, null: true
    end

    change_table :archived_pull_requests, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :repository_id, :bigint, unsigned: true, null: false
      t.change :user_id, :bigint, unsigned: true, default: nil
      t.change :base_repository_id, :bigint, unsigned: true, null: true
      t.change :head_repository_id, :bigint, unsigned: true, null: true
      t.change :base_user_id, :bigint, unsigned: true, null: true
      t.change :head_user_id, :bigint, unsigned: true, null: true
    end
  end

  def down
    change_table :pull_requests, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :repository_id, :int, null: false
      t.change :user_id, :int, default: nil
      t.change :base_repository_id, :int, default: nil
      t.change :head_repository_id, :int, default: nil
      t.change :base_user_id, :int, default: nil
      t.change :head_user_id, :int, default: nil
    end

    change_table :archived_pull_requests, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :repository_id, :int, null: false
      t.change :user_id, :int, default: nil
      t.change :base_repository_id, :int, default: nil
      t.change :head_repository_id, :int, default: nil
      t.change :base_user_id, :int, default: nil
      t.change :head_user_id, :int, default: nil
    end
  end
end
