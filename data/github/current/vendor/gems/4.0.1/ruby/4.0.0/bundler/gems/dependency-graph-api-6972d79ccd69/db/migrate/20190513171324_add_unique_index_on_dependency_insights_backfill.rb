class AddUniqueIndexOnDependencyInsightsBackfill < ActiveRecord::Migration[5.2]
  def change
    remove_index :dg_dep_insights_backfills, name: :index_dg_dep_insights_backfills_on_github_owner_id, column: :github_owner_id
    add_index :dg_dep_insights_backfills, :github_owner_id, unique: true
  end
end
