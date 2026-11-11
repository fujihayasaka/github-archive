# frozen_string_literal: true

class AddAccountSettingsOnUpdateConfigs < ActiveRecord::Migration[6.0]
  def change
    add_column :update_configs, :update_schedule_time_of_day, :time
    add_column :update_configs, :update_schedule_day_of_week, :string, limit: 10
    add_column :update_configs, :update_schedule_timezone, :string, limit: 30
    add_column :update_configs, :pull_request_branch_name_separator, :string,
               limit: 1
    add_column :update_configs, :open_pull_requests_limit, :integer
    add_column :update_configs, :rebase_strategy, :string, limit: 30
  end
end
