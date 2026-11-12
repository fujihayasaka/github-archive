class CreateRepositories < ActiveRecord::Migration[5.0]
  def change
    create_table :repositories, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|

      t.timestamps
    end
  end
end
