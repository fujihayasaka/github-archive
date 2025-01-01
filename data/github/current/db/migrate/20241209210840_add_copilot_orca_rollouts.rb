# typed: true
# frozen_string_literal: true

class AddCopilotOrcaRollouts < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Copilot

  def change
    create_table :orca_rollouts, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :organization,
        type: :bigint,
        unsigned: true,
        null: false,
        index: { unique: false }

      t.references :orca_pipeline_group,
        type: :bigint,
        unsigned: true,
        null: false,
        index: { unique: false }

      t.references :control_model,
        type: :bigint,
        unsigned: true,
        null: true,
        index: { unique: false }

      t.references :treatment_model,
        type: :bigint,
        unsigned: true,
        null: true,
        index: { unique: false }

      t.integer :percentage,
        unsigned: true,
        null: false,
        default: 0

      t.datetime :evaluation_started_at,
        precision: 6,
        null: true

      t.integer :evaluation_duration,
        unsigned: true,
        null: true

      t.string :status,
        limit: 16,
        type: 'enum("ready", "active", "evaluating", "completed", "disabled")',
        null: false,
        default: "ready"

      t.timestamps precision: 6
    end
  end
end
