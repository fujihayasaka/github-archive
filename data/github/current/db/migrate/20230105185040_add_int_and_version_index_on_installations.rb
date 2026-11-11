# typed: true
# frozen_string_literal: true

class AddIntAndVersionIndexOnInstallations < ActiveRecord::Migration[7.1]
  def up
    change_table :integration_installations, bulk: true do |t|
      t.index [:integration_id, :integration_version_number], name: "index_on_integration_id_and_version_number"

      t.change :integration_id,                 :bigint, unsigned: true, null: false
      t.change :target_id,                      :bigint, unsigned: true, null: false
      t.change :integration_version_id,         :bigint, unsigned: true, null: false
      t.change :contact_email_id,               :bigint, unsigned: true, null: true
      t.change :subscription_item_id,           :bigint, unsigned: true, null: true
      t.change :integration_install_trigger_id, :bigint, unsigned: true, null: true
      t.change :user_suspended_by_id,           :bigint, unsigned: true, null: true
    end
  end

  def down
    change_table :integration_installations, bulk: true do |t|
      t.change :user_suspended_by_id,           :int, null: true
      t.change :integration_install_trigger_id, :int, null: true
      t.change :subscription_item_id,           :int, null: true
      t.change :contact_email_id,               :int, null: true
      t.change :integration_version_id,         :int, null: false
      t.change :target_id,                      :int, null: false
      t.change :integration_id,                 :int, null: false

      t.remove_index name: "index_on_integration_id_and_version_number"
    end
  end
end
