# frozen_string_literal: true

class AddRequiredInstanceSizeColumn < ActiveRecord::Migration[6.0]
  def change
    add_column :update_configs, :required_instance_size, :string, limit: 20
  end
end
