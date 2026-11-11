# frozen_string_literal: true

class AddAutomergeBlockedToPr < ActiveRecord::Migration[6.0]
  def change
    add_column(:pull_requests, :automerge_block_requested, :boolean)
  end
end
