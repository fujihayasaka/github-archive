# frozen_string_literal: true

class AddDryRunFlagToUpdateJob < ActiveRecord::Migration[6.0]
  def change
    add_column :update_jobs, :dry_run, :boolean, default: false, null: false
  end
end
