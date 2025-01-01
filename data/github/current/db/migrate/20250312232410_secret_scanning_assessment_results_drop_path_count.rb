# typed: true

# rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys
class SecretScanningAssessmentResultsDropPathCount < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def change
    change_table :secret_scanning_assessment_results, bulk: true do |t|
      t.column :updated_at, :datetime, null: true, precision: 6
      t.remove :num_unique_paths, type: "int", null: false, unsigned: true, default: "0", comment: "the number of unique paths which had secrets in the repo"
    end
  end
end
