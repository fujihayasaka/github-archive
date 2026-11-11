# frozen_string_literal: true

class DropIncludeAdvisoriesOnPublicReposColumn < ActiveRecord::Migration[6.0]
  def change
    remove_column :accounts, :include_advisories_on_public_repos, :boolean
  end
end
