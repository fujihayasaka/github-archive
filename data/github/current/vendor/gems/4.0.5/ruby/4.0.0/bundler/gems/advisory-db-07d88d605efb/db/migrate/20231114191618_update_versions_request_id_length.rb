# frozen_string_literal: true

class UpdateVersionsRequestIDLength < ActiveRecord::Migration[7.0]
  def up
    change_column :versions, :request_id, :string, limit: 255, default: nil, collation: "utf8mb4_general_ci"
  end

  def down
    change_column :versions, :request_id, :string, limit: 36, default: nil, collation: "utf8mb4_general_ci"
  end
end
