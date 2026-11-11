# frozen_string_literal: true

class AddGhsaIdToUpdateJob < ActiveRecord::Migration[7.0]
  def change
    add_column :update_jobs, :triggered_by_ghsa_id, :string, limit: 19
  end
end
