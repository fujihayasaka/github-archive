# typed: true

class AddModeToSecretScanningBypassReviewers < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    add_column :secret_scanning_bypass_reviewers, :mode, :tinyint, after: :security_configuration_id, unsigned: true, null: false, default: 0, comment: "The bypass mode. See BypassMode enum in github-ui. Default is ALWAYS"
  end
end
