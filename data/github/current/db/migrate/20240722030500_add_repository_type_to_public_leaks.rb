# typed: true
class AddRepositoryTypeToPublicLeaks < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    change_table :secret_scanning_public_leaks, bulk: true do |t|
      t.column :repository_type, :tinyint, unsigned: true, null: false, comment: "the type of repo where this leak was found, from Spokes::Repository::RepositoryType, to support gists and other non-repo repos"
    end
  end
end
