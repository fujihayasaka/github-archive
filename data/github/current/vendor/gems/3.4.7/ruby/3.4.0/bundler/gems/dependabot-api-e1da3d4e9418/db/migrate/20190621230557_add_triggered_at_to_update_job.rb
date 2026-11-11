# frozen_string_literal: true

class AddTriggeredAtToUpdateJob < ActiveRecord::Migration[6.0]
  def change
    add_column :update_jobs, :triggered_at, :datetime, null: true
  end
end
