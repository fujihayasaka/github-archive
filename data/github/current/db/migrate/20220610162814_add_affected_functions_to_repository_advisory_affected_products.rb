# typed: true
# frozen_string_literal: true

class AddAffectedFunctionsToRepositoryAdvisoryAffectedProducts < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    change_table :repository_advisory_affected_products, bulk: true do |t|
      t.column :affected_functions, :string, limit: 1024, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
    end
  end
end
