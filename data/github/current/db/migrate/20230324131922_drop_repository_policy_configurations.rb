# typed: true
# frozen_string_literal: true

class DropRepositoryPolicyConfigurations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    drop_table :repository_policy_configurations, if_exists: true
  end
end
