# frozen_string_literal: true

class DropGitHubSecurityAdvisoriesTable < ActiveRecord::Migration[7.0]
  def up
    drop_table :github_security_advisories
  end

  def down
    create_table :github_security_advisories, charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.string :ghsa_id, limit: 19, null: false
      t.string :dependency_name, limit: 255, null: false
      t.string :package_manager, limit: 20, null: false
      t.text :affected_versions
      t.text :patched_versions
      t.datetime :published_at, null: true
      t.datetime :withdrawn_at, null: true
      t.timestamps
      t.datetime :github_updated_at, null: false
    end

    change_table :github_security_advisories, bulk: true do |t|
      t.index %i(ghsa_id package_manager dependency_name), name: :index_ghsa_dependency, unique: true
      t.index %i(package_manager dependency_name), name: :index_ghsa_package_dependency
    end
  end
end
