# typed: true
# frozen_string_literal: true

class AddVersionToSecurityConfigurations < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    add_column :security_configurations, :version, :integer, unsigned: true, null: false, default: 0
  end
end
