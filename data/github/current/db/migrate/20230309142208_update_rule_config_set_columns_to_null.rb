# typed: true
# frozen_string_literal: true

class UpdateRuleConfigSetColumnsToNull < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def up
    change_table :repository_rule_configurations, bulk: true do |t|
      t.change_null :source_id, true
      t.change_null :source_type, true
      t.change_null :target, true
    end
  end

  def down
    change_table :repository_rule_configurations, bulk: true do |t|
      t.change_null :source_id, false
      t.change_null :source_type, false
      t.change_null :target, false
    end
  end
end
