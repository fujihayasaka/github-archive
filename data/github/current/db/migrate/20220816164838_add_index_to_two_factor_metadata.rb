# typed: true
class AddIndexToTwoFactorMetadata < ActiveRecord::Migration[7.1]
  def change
    add_index :two_factor_requirement_metadata, :last_email_notified_at, unique: false, name: "index_last_email_notified_at"
  end
end
