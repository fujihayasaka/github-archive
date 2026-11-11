# typed: true
# frozen_string_literal: true

# Migration for Policy Studio schema - creates copilot_policies table.
#
# See: https://github.com/github/Copilot-Controls/issues/662
class CreateCopilotPolicies < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    # Create the copilot_policies table for policy definitions managed via stafftools
    create_table :copilot_policies, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :config_name, limit: 255, null: false
      t.string :display_name, limit: 255, null: false
      t.json :description, null: false, comment: "Nested structure with business/org/user descriptions"
      t.json :policy_config, null: false, comment: "Scalar policy configuration"
      t.json :plans, null: false, comment: "Array of plan strings that have access to this policy"
      t.string :feature_flag, limit: 255, null: true
      t.string :created_by_login, limit: 255, null: false, comment: "Username of Hubber who created this in Stafftools"
      t.text :github_issue_url, null: true, comment: "GitHub issue with more details about the policy"
      t.timestamps

      t.index :config_name, unique: true
    end
  end
end
