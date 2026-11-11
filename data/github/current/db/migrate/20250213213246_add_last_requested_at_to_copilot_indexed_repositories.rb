# typed: true
# frozen_string_literal: true

class AddLastRequestedAtToCopilotIndexedRepositories < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::Copilot
  def change
    change_table :copilot_indexed_repositories, bulk: true do |t|
      t.column :last_requested_at, :timestamp, null: false,  default: -> { "CURRENT_TIMESTAMP()" }, comment: "The last time the repo was requested for indexing or search"
      t.index  [:last_requested_at, :repository_id], name: "index_on_last_requested_at_and_repository_id"
    end
  end
end
