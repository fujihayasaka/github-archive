# frozen_string_literal: true

class AddVendorFlagToUpdateConfig < ActiveRecord::Migration[6.0]
  def change
    add_column :update_configs, :vendor, :boolean, default: false, null: false
  end
end
