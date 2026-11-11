# frozen_string_literal: true

class AddNotNullConstraintsUpdateConfig < ActiveRecord::Migration[6.0]
  def change
    change_column_null(:update_configs, :update_schedule_time_of_day, false)
    change_column_null(:update_configs, :update_schedule_day_of_week, false)
    change_column_null(:update_configs, :update_schedule_timezone, false)
    change_column_null(:update_configs, :pull_request_branch_name_separator, false)
    change_column_null(:update_configs, :open_pull_requests_limit, false)
    change_column_null(:update_configs, :rebase_strategy, false)
  end
end
