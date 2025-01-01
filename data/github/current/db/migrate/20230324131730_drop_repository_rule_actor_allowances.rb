# typed: true
# frozen_string_literal: true

class DropRepositoryRuleActorAllowances < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    drop_table :repository_rule_actor_allowances, if_exists: true
  end
end
