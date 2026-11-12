# frozen_string_literal: true

class AddIndexToReposOnPausedAtandWillPauseAt < ActiveRecord::Migration[7.0]
  def change
    add_index :repos, %i(will_pause_at paused_at)
  end
end
