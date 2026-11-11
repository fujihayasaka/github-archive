# frozen_string_literal: true

class ChangeAutomergeBlockRequestedDefault < ActiveRecord::Migration[6.0]
  def change
    change_column_default(
      :pull_requests, :automerge_block_requested,
      from: nil,
      to: false,
    )
  end
end
