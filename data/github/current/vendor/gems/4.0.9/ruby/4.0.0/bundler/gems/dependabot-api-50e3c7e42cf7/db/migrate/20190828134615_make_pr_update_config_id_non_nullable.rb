# frozen_string_literal: true

class MakePrUpdateConfigIdNonNullable < ActiveRecord::Migration[6.0]
  def change
    change_column_null :pull_requests, :update_config_id, false
  end
end
