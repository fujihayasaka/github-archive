class AddStars < ActiveRecord::Migration[5.0]
  def change
    create_table :star_counts, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.integer :github_repository_id, index: true, null: false
      t.integer :star_count, default: 0
    end
  end
end
