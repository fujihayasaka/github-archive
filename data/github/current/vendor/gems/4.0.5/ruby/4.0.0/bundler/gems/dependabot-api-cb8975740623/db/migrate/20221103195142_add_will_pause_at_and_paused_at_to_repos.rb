# frozen_string_literal: true

class AddWillPauseAtAndPausedAtToRepos < ActiveRecord::Migration[7.0]
  def change
    add_column :repos, :will_pause_at, :datetime
    add_column :repos, :paused_at, :datetime
  end
end
