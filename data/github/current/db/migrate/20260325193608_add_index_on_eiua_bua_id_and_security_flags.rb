# typed: true
# frozen_string_literal: true

class AddIndexOnEiuaBuaIdAndSecurityFlags < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change # -- intentionally keeping the old single-column index
    # until the composite index is validated in production
    add_index :enterprise_installation_user_accounts,
      [:business_user_account_id, :using_advanced_security, :using_code_security, :using_secret_protection],
      name: :idx_eiua_on_bua_id_and_security_flags
  end
end
