# typed: true
# frozen_string_literal: true

class AddCheckedForConfigFileToSecretScanningRepos < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def change
    change_table :secret_scanning_repositories, bulk: true do |t|
      t.binary :checked_for_config_file_branch, limit: 1024, null: true, comment: "branch whose config file has OID in checked_for_config_file_oid"
      t.string :checked_for_config_file_oid, limit: 40, null: true, comment: "OID of the config file in branch in checked_for_config_file_branch"
    end
  end
end
