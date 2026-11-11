class AddGenericSecretsColumnToSecretScanningRepos < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def up
    change_table(:secret_scanning_repos, bulk: true) do |t|
      t.column :generic_secrets_enabled, :boolean, null: false, default: false, comment: "whether Generic Secrets is enabled for this repository"
    end
  end

  def down
    change_table(:secret_scanning_repos, bulk: true) do |t|
      t.remove :generic_secrets_enabled
    end
  end
end
