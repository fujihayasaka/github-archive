class AddRepositories < ActiveRecord::Migration[5.0]
  def change
    create_table :repositories, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.integer :github_repository_id, null: false
      t.boolean :public, default: true
      t.timestamps
    end

    add_index :repositories, :github_repository_id, unique: true
  end
end
