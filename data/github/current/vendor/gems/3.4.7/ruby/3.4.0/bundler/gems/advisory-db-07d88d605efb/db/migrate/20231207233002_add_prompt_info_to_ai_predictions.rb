# frozen_string_literal: true

class AddPromptInfoToAiPredictions < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_predictions, :summary, :text
    add_column :ai_predictions, :description, :text
    add_column :ai_predictions, :prompt, :text
    add_column :ai_predictions, :raw_prediction_output, :text
  end
end
