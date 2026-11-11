# frozen_string_literal: true

class AllowNullableDirectory < ActiveRecord::Migration[7.0]
  def change
    change_column_null(:update_configs, :directory, true)
  end
end
