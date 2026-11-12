# frozen_string_literal: true

class AddIndexToUpdateConfigsOnUpdateScheduleAndRepoId < ActiveRecord::Migration[7.0]
  def change
    add_index :update_configs, %i(update_schedule repo_id)
  end
end
