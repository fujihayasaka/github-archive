# typed: true
# frozen_string_literal: true

class RepositoriesPushesSha256AuthenticCommits < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::RepositoriesPushes)

  def up
    change_table :authentic_commits, bulk: true do |t|
      t.change :oid, "varbinary(32)", null: false
    end
  end

  def down
    change_table :authentic_commits, bulk: true do |t|
      t.change :oid, "binary(20)", null: false
    end
  end
end
