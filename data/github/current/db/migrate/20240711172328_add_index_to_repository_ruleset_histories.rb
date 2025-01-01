# typed: true
# frozen_string_literal: true

class AddIndexToRepositoryRulesetHistories < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    add_index :repository_ruleset_histories, [:created_at], unique: false, name: "index_repository_ruleset_histories_created_at"
  end
end
