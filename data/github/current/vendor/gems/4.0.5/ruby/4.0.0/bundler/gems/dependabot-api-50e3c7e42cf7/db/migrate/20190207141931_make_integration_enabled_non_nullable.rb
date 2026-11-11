# frozen_string_literal: true

class MakeIntegrationEnabledNonNullable < ActiveRecord::Migration[6.0]
  def change
    CodeshipAccount.update_all(integration_enabled: false)

    change_column_null :codeship_accounts, :integration_enabled, false
  end
end
