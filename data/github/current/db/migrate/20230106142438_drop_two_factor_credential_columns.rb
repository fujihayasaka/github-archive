# typed: true

class DropTwoFactorCredentialColumns < ActiveRecord::Migration[7.1]
  def change
    change_table(:two_factor_credentials, bulk: true) do |t|
      t.remove :delivery_method
      t.remove :secret
      t.remove :sms_number
      t.remove :backup_sms_number
      t.remove :provider
    end
  end
end
