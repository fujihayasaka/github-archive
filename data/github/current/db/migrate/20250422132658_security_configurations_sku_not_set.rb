# typed: true

class SecurityConfigurationsSKUNotSet < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::RepositoriesNotify

  def change
    change_table :security_configurations, bulk: true do |t|
      t.change :code_security_sku_enabled, "tinyint(1)", null: true, default: nil
      t.change :secret_protection_sku_enabled, "tinyint(1)", null: true, default: nil
    end
  end
end
