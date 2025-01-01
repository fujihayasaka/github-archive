# typed: true

class DropUnusedCheckSuitesIndexes < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesActionsChecks)

  def change
    change_table :check_suites, bulk: true do |t|
      t.remove_index [:name], name: "index_check_suites_on_name"
      t.remove_index [:archived_at], name: "index_check_suites_on_archived_at"
    end
  end
end
