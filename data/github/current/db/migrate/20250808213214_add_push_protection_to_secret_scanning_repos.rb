# typed: true
# frozen_string_literal: true

class AddPushProtectionToSecretScanningRepos < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def change
    change_table :secret_scanning_repos, bulk: true do |t|
      t.boolean :push_protection, null: false, default: false, comment: "whether push protection is enabled for this repository"
    end
  end
end
