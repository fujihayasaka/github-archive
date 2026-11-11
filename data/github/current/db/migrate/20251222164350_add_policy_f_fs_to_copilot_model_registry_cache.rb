# typed: true

class AddPolicyFFsToCopilotModelRegistryCache < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :model_registry_cache, bulk: true do |t|
      t.column :policy_pro_feature_flag, :string, limit: 128, null: true, comment: "Feature flag for Policy Pro access"
      t.column :policy_ga_feature_flag, :string, limit: 128, null: true, comment: "Feature flag for Policy GA access"
      t.column :policy_rollout_complete_feature_flag, :string, limit: 128, null: true, comment: "Feature flag indicating completion of Policy rollout"
    end
  end
end
