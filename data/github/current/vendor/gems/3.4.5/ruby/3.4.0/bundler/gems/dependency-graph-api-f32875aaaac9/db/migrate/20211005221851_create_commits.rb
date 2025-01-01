class CreateCommits < ActiveRecord::Migration[6.0]
  def change
    create_table :dg_commits, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.integer :github_repository_id, null: false, unsigned: true
      t.string :ref, null: false
      t.column :sha, "char(64)", null: false
      t.boolean :default_branch, null: false
      t.datetime :event_time, null: false

      t.timestamps
    end

    add_index :dg_commits, [:github_repository_id, :event_time, :default_branch], name: "index_dg_commits_on_gh_repo_id_event_time_and_default_branch"
    add_index :dg_commits, [:github_repository_id, :ref, :event_time], name: "index_dg_commits_on_gh_repo_id_ref_and_event_time"
  end
end
