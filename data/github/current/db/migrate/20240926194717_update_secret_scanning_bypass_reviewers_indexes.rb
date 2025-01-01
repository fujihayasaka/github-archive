# typed: true

class UpdateSecretScanningBypassReviewersIndexes < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    change_table(:secret_scanning_bypass_reviewers, bulk: true) do |t|
      t.remove_index name: "idx_on_owner_scope_id_reviewer_id_reviewer_type_291fb3edb1"
      t.index [:owner_scope_id, :security_configuration_id, :reviewer_id, :reviewer_type], name: "idx_owner_scope_id_security_config_id_reviewer_id_and_type", unique: true # rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
    end
  end

  def down
    change_table(:secret_scanning_bypass_reviewers, bulk: true) do |t|
      t.index [:owner_scope_id, :reviewer_id, :reviewer_type], name: "idx_on_owner_scope_id_reviewer_id_reviewer_type_291fb3edb1", unique: true
      t.remove_index name: "idx_owner_scope_id_security_config_id_reviewer_id_and_type"
    end
  end
end
