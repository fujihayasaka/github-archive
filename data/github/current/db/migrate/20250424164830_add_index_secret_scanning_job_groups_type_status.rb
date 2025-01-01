# typed: true

class AddIndexSecretScanningJobGroupsTypeStatus < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  sig { void }
  def change
    add_index :secret_scanning_job_groups, [:type, :status], name: "idx_secret_scanning_job_groups_type_status"
  end
end
