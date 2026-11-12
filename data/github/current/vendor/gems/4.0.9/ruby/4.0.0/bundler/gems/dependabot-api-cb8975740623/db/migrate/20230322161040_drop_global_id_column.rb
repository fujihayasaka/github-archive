# frozen_string_literal: true

class DropGlobalIdColumn < ActiveRecord::Migration[7.0]
  def change
    remove_column :repos, :github_node_id, "varchar(255)"
  end
end
