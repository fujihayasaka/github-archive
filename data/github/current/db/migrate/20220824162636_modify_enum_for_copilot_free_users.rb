# typed: true

class ModifyEnumForCopilotFreeUsers < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def up
    change_column :copilot_complimentary_users, :free_user_type, :string, limit: 50, null: false, comment: "the type of the free user"
  end

  def down
    change_column :copilot_complimentary_users, :free_user_type, "enum('EngagedOSS','Enterprise', 'EnterpriseTrial', 'Educational')", null: false, comment: "the type of the free user"
  end
end
