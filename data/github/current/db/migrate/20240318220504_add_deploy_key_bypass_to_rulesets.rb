# typed: true
# frozen_string_literal: true

class AddDeployKeyBypassToRulesets < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    change_table :repository_rulesets, bulk: true do |t|
      t.column :deploy_key_bypass, :boolean, default: false, null: false
    end
  end
end
