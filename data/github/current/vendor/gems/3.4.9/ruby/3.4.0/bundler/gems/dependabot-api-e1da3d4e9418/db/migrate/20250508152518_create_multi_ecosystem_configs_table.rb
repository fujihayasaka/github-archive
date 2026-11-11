# frozen_string_literal: true

class CreateMultiEcosystemConfigsTable < ActiveRecord::Migration[7.0]
  def change
    create_table :multi_ecosystem_configs, id: :bigint, unsigned: true, auto_increment: true, charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.string :name
      t.timestamps
    end
  end
end
