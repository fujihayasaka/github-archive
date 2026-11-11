# frozen_string_literal: true

class RenameGroupRulesToGroups < ActiveRecord::Migration[7.0]
  def change
    rename_table :group_rules, :groups

    add_column :groups, :rules, :text, charset: "utf8mb4", collation: "utf8mb4_general_ci"

    rename_table :groups, :dependency_groups
  end
end
