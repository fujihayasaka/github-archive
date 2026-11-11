# typed: true
# frozen_string_literal: true

class DropResourceGroup < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def up
    drop_table :workspace_resource_groups, if_exists: true
  end

  def down
  end
end
