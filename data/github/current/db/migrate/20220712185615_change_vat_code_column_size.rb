# typed: true
class ChangeVatCodeColumnSize < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def up
    change_column :user_personal_profiles, :vat_code, :string, null: true, limit: 50
  end

  def down
    change_column :user_personal_profiles, :vat_code, :string, null: true, limit: 64
  end
end
