# frozen_string_literal: true

class VulnerabilitiesOnPublicRepos < ActiveRecord::Migration[6.0]
  def change
    add_column :accounts, :include_advisories_on_public_repos, :boolean
  end
end
