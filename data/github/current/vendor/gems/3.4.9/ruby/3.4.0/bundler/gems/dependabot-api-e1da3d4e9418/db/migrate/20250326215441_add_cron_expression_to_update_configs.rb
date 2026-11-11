# frozen_string_literal: true

class AddCronExpressionToUpdateConfigs < ActiveRecord::Migration[7.0]
  def change
    add_column :update_configs, :update_schedule_cron_expression, :string, limit: 255, null: true, if_not_exists: true
  end
end
