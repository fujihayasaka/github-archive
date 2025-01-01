# frozen_string_literal: true

class AddMlPredictionToFeedEntry < ActiveRecord::Migration[5.2]
  def change
    add_column :feed_entries, :ml_reject_prediction, :integer, default: 0
  end
end
