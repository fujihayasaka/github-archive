# typed: true

# rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys
class SecretScanningAssessmentResultsDefault < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    change_column_default :secret_scanning_assessment_results, :num_unique_paths, from: nil, to: 0
  end
end
