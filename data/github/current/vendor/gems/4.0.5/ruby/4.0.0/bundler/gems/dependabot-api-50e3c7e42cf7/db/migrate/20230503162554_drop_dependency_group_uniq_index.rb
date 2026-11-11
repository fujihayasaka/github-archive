# frozen_string_literal: true

class DropDependencyGroupUniqIndex < ActiveRecord::Migration[7.0]
  def up
    remove_index :dependency_groups, %i(name update_config_id)
  end

  def down
    add_index :dependency_groups, %i(name update_config_id), unique: true, name: index_name
  end

  private

  def index_name
    "index_dependency_groups_on_name_and_update_config_id"
  end
end
