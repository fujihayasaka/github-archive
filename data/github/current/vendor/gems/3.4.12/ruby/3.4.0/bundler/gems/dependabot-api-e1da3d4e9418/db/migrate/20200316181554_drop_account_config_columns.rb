# frozen_string_literal: true

class DropAccountConfigColumns < ActiveRecord::Migration[6.0]
  def change
    remove_column :accounts, :weekly_update_run_day, :time, default: "monday"
    remove_column :accounts, :update_run_time, :string, limit: 10,
                                                        default: "05:00"
    remove_column :accounts, :timezone, :string, limit: 30, default: "UTC"
    remove_column :accounts, :branch_name_separator, :string, limit: 1,
                                                              default: "/"
    remove_column :accounts, :open_pull_requests_limit, :integer, default: 5
    remove_column :accounts, :automatically_rebase_prs, :string, limit: 30,
                                                                 default: true
    remove_column :accounts, :only_automerge_during_working_hours, :bool,
                  default: false
    remove_column :accounts, :automerge_working_hours, :text
  end
end
