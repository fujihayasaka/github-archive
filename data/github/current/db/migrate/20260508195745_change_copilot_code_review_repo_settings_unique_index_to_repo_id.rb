# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
class ChangeCopilotCodeReviewRepoSettingsUniqueIndexToRepoId < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table :copilot_code_review_repository_settings, bulk: true do |t|
      t.remove_index name: "index_ccr_repo_settings_on_repo_id_custom_instructions_enabled"
      t.index :repository_id, unique: true, name: "index_ccr_repo_settings_on_repository_id"
    end
  end
end
# rubocop:enable GitHub/DoNotAddUniqueIndexToExistingColumn
