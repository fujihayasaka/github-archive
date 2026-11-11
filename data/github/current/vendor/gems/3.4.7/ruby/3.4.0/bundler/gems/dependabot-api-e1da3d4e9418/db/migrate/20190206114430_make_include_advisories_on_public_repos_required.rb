# frozen_string_literal: true

class MakeIncludeAdvisoriesOnPublicReposRequired < ActiveRecord::Migration[6.0]
  def change
    Account.update_all(include_advisories_on_public_repos: true)

    change_column_null :accounts, :include_advisories_on_public_repos, false
  end
end
