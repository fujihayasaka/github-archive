# frozen_string_literal: true

class AddFeatureFlagColumnToCodeshipAccounts < ActiveRecord::Migration[6.0]
  def change
    add_column :codeship_accounts, :integration_enabled, :boolean
  end
end
