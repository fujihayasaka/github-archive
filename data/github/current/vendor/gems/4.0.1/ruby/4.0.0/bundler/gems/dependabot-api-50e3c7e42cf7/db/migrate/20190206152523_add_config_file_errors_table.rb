# frozen_string_literal: true

class AddConfigFileErrorsTable < ActiveRecord::Migration[6.0]
  def change
    create_table :config_file_errors, charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.bigint :repo_id, null: false
      t.json :error_details, null: false
      t.string :error_type, null: false
      t.timestamps
    end

    add_foreign_key :config_file_errors, :repos
  end
end
