# frozen_string_literal: true

class AddRequestIDToVersions < ActiveRecord::Migration[6.1]
  def change
    add_column :versions, :request_id, :string, limit: 36
  end
end
