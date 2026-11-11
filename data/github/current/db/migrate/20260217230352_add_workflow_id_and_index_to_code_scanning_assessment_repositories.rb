# typed: true
# frozen_string_literal: true

class AddWorkflowIdAndIndexToCodeScanningAssessmentRepositories < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::SecurityProductsEnablement)

  def change
    change_table :code_scanning_assessment_repositories, bulk: true do |t|
      t.string :workflow_id, limit: 255, null: true
      t.index [:status, :created_at], name: "index_status_and_created_at"
    end
  end
end
