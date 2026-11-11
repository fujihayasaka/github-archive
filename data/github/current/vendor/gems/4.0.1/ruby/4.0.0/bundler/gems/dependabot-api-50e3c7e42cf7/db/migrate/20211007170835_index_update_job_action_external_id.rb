# frozen_string_literal: true

class IndexUpdateJobActionExternalId < ActiveRecord::Migration[6.0]
  def change
    add_index :update_jobs, :actions_external_id, unique: true
  end
end
