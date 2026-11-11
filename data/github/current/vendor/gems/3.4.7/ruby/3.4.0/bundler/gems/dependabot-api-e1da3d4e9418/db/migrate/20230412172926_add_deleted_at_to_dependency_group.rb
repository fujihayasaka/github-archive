# frozen_string_literal: true

# rubocop:disable Rails/BulkChangeTable
class AddDeletedAtToDependencyGroup < ActiveRecord::Migration[7.0]
  def change
    add_column :dependency_groups, :deleted_at, :datetime
    remove_index :dependency_groups, :update_config_id
    add_index :dependency_groups, %i(update_config_id deleted_at), name: index_name
  end

  def index_name
    "index_dependency_groups_on_update_config_id_and_deleted_at"
  end
end
# rubocop:enable Rails/BulkChangeTable
