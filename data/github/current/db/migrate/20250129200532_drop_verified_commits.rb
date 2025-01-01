# typed: true

# rubocop:disable GitHub/ConnectionClassPresentInMigration

class DropVerifiedCommits < ActiveRecord::Migration[8.1]
  def change
    if GitHub.enterprise?
      drop_table :verified_commits
    end
  end
end
