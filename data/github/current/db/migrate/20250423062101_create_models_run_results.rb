# typed: true

class CreateModelsRunResults < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::GitHubModels)

  def change
    create_table :models_run_results, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, null: false, unsigned: true
      t.bigint :user_id, null: true, unsigned: true
      t.json :results, null: true
      t.column :target_branch, "varbinary(1024)", null: true, default: nil

      t.timestamps

      t.index [:repository_id, :target_branch], name: "index_models_run_results_on_repository_id_and_target_branch"
    end
  end
end
