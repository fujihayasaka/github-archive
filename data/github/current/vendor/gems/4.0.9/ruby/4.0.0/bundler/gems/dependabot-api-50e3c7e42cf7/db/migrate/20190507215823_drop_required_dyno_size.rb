# frozen_string_literal: true

class DropRequiredDynoSize < ActiveRecord::Migration[6.0]
  def change
    remove_column :update_configs, :required_dyno_size, :string, limit: 20
  end
end
