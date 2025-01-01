# typed: true

class AddContentWarningColumnsToNetworkPrivileges < ActiveRecord::Migration[7.1]
  use_connection_class(ApplicationRecord::Domain::Repositories)

  def up
    change_table :network_privileges, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :repository_id, :bigint, unsigned: true

      t.boolean :show_content_warning, null: false, default: false
      t.text :content_warning_category, null: true
      t.text :content_warning_sub_category, null: true
      t.text :content_warning_custom_sub_category, null: true
    end
  end

  def down
    change_table :network_privileges, bulk: true do |t|
      t.change :id, :int, unsigned: true
      t.change :repository_id, :int, unsigned: true

      t.remove :show_content_warning
      t.remove :content_warning_category
      t.remove :content_warning_sub_category
      t.remove :content_warning_custom_sub_category
    end
  end
end
