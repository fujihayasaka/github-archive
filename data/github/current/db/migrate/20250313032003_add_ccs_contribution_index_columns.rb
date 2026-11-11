# typed: true

class AddCcsContributionIndexColumns < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    change_table :commit_contribution_summaries, bulk: true do |t|
      t.column :last_contribution_index, :smallint, null: true, unsigned: true, after: :total_count
      t.column :first_contribution_index, :smallint, null: true, unsigned: true, after: :total_count
    end
  end
end
