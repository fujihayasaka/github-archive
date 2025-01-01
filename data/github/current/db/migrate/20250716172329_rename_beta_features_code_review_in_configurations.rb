# typed: true
# frozen_string_literal: true

class RenameBetaFeaturesCodeReviewInConfigurations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def up
    change_table :copilot_configurations, bulk: true do |t|
      t.column :code_review_beta_features, :integer, limit: 1, null: false, default: 0, comment: "Policy for beta features usage by Copilot Code Review"
      t.remove  :beta_features_code_review
    end
  end

  def down
    change_table :copilot_configurations, bulk: true do |t|
      t.column :beta_features_code_review, :integer, limit: 1, null: false, default: 0, comment: "Policy for beta features usage by Copilot Code Review"
      t.remove  :code_review_beta_features
    end
  end
end
