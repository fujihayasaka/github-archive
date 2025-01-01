# typed: true

class NotNullTwoFactorCredentialColumns < ActiveRecord::Migration[7.1]
  def up
    change_table(:two_factor_credentials, bulk: true) do |t|
      t.change :delivery_method, "varchar(255)", null: true, default: nil
      t.change :secret, "varchar(255)", null: true
    end
  end

  def down
    change_table(:two_factor_credentials, bulk: true) do |t|
      t.change :delivery_method, "varchar(255)", null: false, default: "app"
      t.change :secret, "varchar(255)", null: false
    end
  end
end
