# typed: true
# frozen_string_literal: true

class ChangeCommitContributionsCharset < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def up
    connection.execute "ALTER TABLE `commit_contributions` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci;"
  end

  def down
    connection.execute "ALTER TABLE `commit_contributions` CONVERT TO CHARACTER SET utf8mb3;"
  end
end
