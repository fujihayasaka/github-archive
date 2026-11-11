# frozen_string_literal: true

class AddFirecrackerColumnToUpdateJob < ActiveRecord::Migration[6.0]
  def change
    add_column :update_jobs, :firecracker, :boolean, default: false
  end
end
