class AddWeeklyCommitContributionSummaries < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    create_table :weekly_commit_contribution_summaries, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :user_id, :bigint, null: false, unsigned: true
      t.column :repository_id, :bigint, null: false, unsigned: true
      t.column :year, :smallint, null: false, unsigned: true
      t.column :total_count, :bigint, null: false, unsigned: true
      t.column :counts, :blob, null: false

      t.index [:user_id, :repository_id, :year], unique: true
      t.index [:repository_id]

      t.timestamps
    end
  end
end
