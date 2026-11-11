# typed: true
# frozen_string_literal: true

class AddGitHubOrMsftToSecretScanningRepos < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    add_column :secret_scanning_repos, :github_or_msft, :boolean, null: false, default: false,
      comment: "Indicates whether the repository is associated with GitHub or Microsoft (internally owned)."
  end
end
