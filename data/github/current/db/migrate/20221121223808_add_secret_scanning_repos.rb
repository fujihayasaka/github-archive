# typed: true

class AddSecretScanningRepos < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    create_table :secret_scanning_repos, id: :bigint, default: nil, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci", comment: "table of repositories; id is the repository id" do |t|
      t.datetime :full_refresh_source_updated_at, null: false, precision: 6, comment: "the updated_at value from the source repository model that was used to perform the last full refresh"
      t.bigint :owner_scope_id, unsigned: true, null: false, comment: "the owner_scopes.id of the user or organization which owns the repository"
      t.bigint :business_id, unsigned: true, null: true, comment: "the enterprise, if any, which owns the repository.  This will be non-nil for both users and organizations which are part of a business."
      t.column :visibility, "enum('PUBLIC', 'PRIVATE', 'INTERNAL')", null: false
      t.column :default_ref, "varbinary(1024)", null: true, comment: "the default ref name of the repository"
      t.bigint :parent_repository_id, unsigned: true, null: true, comment: "if null, this is a top-level repository.  If non-null, this is a direct fork of the ID specified"
      t.boolean :checked_for_config_file, null: true, comment: "true if the current default_ref has been checked for the secret scanning config file; otherwise false.  Null if it was never checked"
      t.column :scanning_config_file_blob_oid, "varchar(64)", charset: "ascii", collation: "ascii_general_ci", null: true, comment: "the blob oid of the secret scanning config file, if it exists on the current default_ref"

      t.boolean :scannable, null: false, default: false, comment: "true if the repository is scannable. a repository is not scannable if it is public and has been staff disabled, or it is private and not GHAS secret-scanning enabled"
      t.boolean :ghas_secret_scanning_enabled, null: false, default: false, comment: "true if the repository is ghas_secret_scanning_enabled; false otherwise"
      t.boolean :results_visible, null: false, default: false, comment: "true if the repository's results are visible to the user false otherwise; visible implies webhooks and notifications, including alerts being visible"
      t.timestamps

      t.index [:owner_scope_id, :results_visible, :visibility], name: "secret_scanning_repos_owner_id", comment: "index for finding all visible repos under a provided owner scope ID"
      t.index [:business_id, :results_visible, :visibility], name: "secret_scanning_repos_business_id", comment: "index for finding all visible repos under a business"
      t.index [:parent_repository_id], name: "secret_scanning_repos_parent_repo_id", comment: "index for finding all child repos"
    end
  end
end
