# typed: true
class AddPreferenceAndRecoveryCodesColumnsToTwoFactorCredentials < ActiveRecord::Migration[7.1]
  def up
    change_table :two_factor_credentials, bulk: true do |t|
      # accompanying changes to satisfy GitHub/ExistingIdColumnsMustBeBigint
      t.change :id, :bigint, unsigned: true, auto_increment: true
      t.change :user_id, :bigint, unsigned: true

      t.column :login_preference, "tinyint(4)", null: true
      t.column :recovery_codes_last_downloaded_at, :datetime, precision: 6, null: true
      t.column :recovery_codes_last_printed_at, :datetime, precision: 6, null: true
    end
  end

  def down
    change_table :two_factor_credentials do |t|
      t.remove :login_preference
      t.remove :recovery_codes_last_downloaded_at
      t.remove :recovery_codes_last_printed_at

      # accompanying changes to satisfy GitHub/ExistingIdColumnsMustBeBigint
      t.change :id, :int, null: false, auto_increment: true
      t.change :user_id, :int
    end
  end
end
