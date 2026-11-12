# frozen_string_literal: true

class ChangeAutomergeBlockRequestedNull < ActiveRecord::Migration[6.0]
  def change
    change_column_null :pull_requests, :automerge_block_requested, false
  end
end
