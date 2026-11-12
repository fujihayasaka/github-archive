# frozen_string_literal: true

class IndexRepoPausedAt < ActiveRecord::Migration[7.0]
  def change
    add_index :repos, %i(paused_at)
  end
end
