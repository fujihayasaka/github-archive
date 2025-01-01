class AddTwoFactorCredentialBannerIndex < ActiveRecord::Migration[7.2]
  def change
    add_index :two_factor_credentials, [:user_id, :created_at, :recovery_codes_last_downloaded_at, :recovery_codes_last_printed_at], unique: false, name: "index_on_user_id_created_at_recovery_codes_downloaded_printed"
  end
end
