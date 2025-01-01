class AddUnqiueIndexToStarCounts < ActiveRecord::Migration[5.2]
  def change
    remove_index :dg_star_counts, :github_repository_id
    add_index :dg_star_counts, :github_repository_id, unique: true
  end
end
