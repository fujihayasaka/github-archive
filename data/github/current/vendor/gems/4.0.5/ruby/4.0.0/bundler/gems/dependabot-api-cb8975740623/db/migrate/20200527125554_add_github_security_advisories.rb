# frozen_string_literal: true

class AddGitHubSecurityAdvisories < ActiveRecord::Migration[6.0]
  def change
    create_table :github_security_advisories, charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.string :ghsa_id, limit: 19, null: false
      t.string :dependency_name, limit: 190, null: false
      t.string :package_manager, limit: 20, null: false
      t.text :affected_versions
      t.text :patched_versions
      t.datetime :published_at, null: true
      t.datetime :withdrawn_at, null: true
      t.timestamps
      t.datetime :github_updated_at, null: false
    end

    add_index :github_security_advisories, :ghsa_id, unique: true
    add_index :github_security_advisories,
              %i(package_manager dependency_name),
              name: :index_ghsa_package_dependency
  end
end
