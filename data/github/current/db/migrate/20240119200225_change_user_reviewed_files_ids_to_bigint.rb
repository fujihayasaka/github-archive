# typed: true
# frozen_string_literal: true

class ChangeUserReviewedFilesIdsToBigint < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def up
    change_table :user_reviewed_files, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :pull_request_id, :bigint, unsigned: true, null: false
      t.change :user_id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table :user_reviewed_files, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :pull_request_id, :int, null: false
      t.change :user_id, :int, null: false
    end
  end
end
