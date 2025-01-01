# typed: true
class AddLowerConfidencePatternsColumnToSecretScanningRepos < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def up
    change_table(:secret_scanning_repos, bulk: true) do |t|
      t.column :lower_confidence_patterns_enabled, :boolean, null: false, default: false, comment: "whether lower confidence patterns are enabled for this repository"
    end
  end

  def down
    change_table(:secret_scanning_repos, bulk: true) do |t|
      t.remove :lower_confidence_patterns_enabled
    end
  end
end
