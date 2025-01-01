# typed: true
# frozen_string_literal: true

class AddCopilotOrcaPipelineGroups < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Copilot

  def change
    create_table :orca_pipeline_groups, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :organization,
        type: :bigint,
        unsigned: true,
        null: false,
        index: { unique: false }

      t.string :name,
        limit: 100,
        null: false

      t.timestamps precision: 6
    end
  end
end
