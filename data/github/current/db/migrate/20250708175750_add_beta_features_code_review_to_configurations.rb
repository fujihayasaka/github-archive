class AddBetaFeaturesCodeReviewToConfigurations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :beta_features_code_review, :integer, limit: 1, null: false, default: 0, comment: "Policy for beta features usage by Copilot Code Review"
    end
  end
end
