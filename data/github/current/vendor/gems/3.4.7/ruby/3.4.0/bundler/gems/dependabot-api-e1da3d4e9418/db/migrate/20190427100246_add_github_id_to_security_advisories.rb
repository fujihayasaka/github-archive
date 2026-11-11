# frozen_string_literal: true

# rubocop:disable Rails/NotNullColumn
class AddGitHubIdToSecurityAdvisories < ActiveRecord::Migration[6.0]
  def change
    remove_column :security_advisories, :source, :string, limit: 40
    add_column :security_advisories, :ghsa_id, :string, limit: 19, null: false

    add_index :security_advisories, :ghsa_id, unique: true
  end
end
# rubocop:enable Rails/NotNullColumn
