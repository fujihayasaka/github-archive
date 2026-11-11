# frozen_string_literal: true

class AddIndexToUpdateConfigsUpdateSchedule < ActiveRecord::Migration[6.0]
  def change
    add_index :update_configs, :update_schedule
  end
end
