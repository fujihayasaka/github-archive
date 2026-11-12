# frozen_string_literal: true

class CreateAIPredictions < ActiveRecord::Migration[7.0]
  def change
    create_table :ai_predictions do |t|
      t.integer :advisory_review_id
      t.integer :feed_entry_id
      t.integer :prediction_id
      t.integer :advisory_state_at_prediction # either predicted at new-update or new-create state for the advisory
      t.string :ai_model
      t.string :predicted_ecosystems
      t.string :predicted_packages
      t.integer :curator_decision, default: 0, limit: 1, null: false
      t.datetime :decided_at

      t.timestamps

      t.index :prediction_id, unique: false
      t.index %i[advisory_review_id curator_decision],
        name: "idx_ai_predictions_advisory_review_id_and_decision",
        unique: false
    end
  end
end
