# frozen_string_literal: true

class AddCommandToUpdateJob < ActiveRecord::Migration[7.0]
  def change
    add_column :update_jobs, :command, :tinyint, default: 0, null: false
  end
end
