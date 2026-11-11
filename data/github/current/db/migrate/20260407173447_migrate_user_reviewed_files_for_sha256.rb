# typed: true
# frozen_string_literal: true

class MigrateUserReviewedFilesForSha256 < ActiveRecord::Migration[8.2]
  use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def up
    change_table :user_reviewed_files, bulk: true do |t|
      t.change :head_sha, :string, limit: 64, null: false
    end
  end

  def down
    change_table :user_reviewed_files, bulk: true do |t|
      t.change :head_sha, "varbinary(40)", null: false
    end
  end
end
