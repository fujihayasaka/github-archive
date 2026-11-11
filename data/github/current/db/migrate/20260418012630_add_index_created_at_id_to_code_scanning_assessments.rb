# typed: true
# frozen_string_literal: true

class AddIndexCreatedAtIdToCodeScanningAssessments < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::SecurityProductsEnablement)

  def change
    add_index :code_scanning_assessments, :created_at, name: "index_created_at"
  end
end
