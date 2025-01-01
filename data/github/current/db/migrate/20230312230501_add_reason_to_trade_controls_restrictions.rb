# typed: true
class AddReasonToTradeControlsRestrictions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    change_table(:trade_controls_restrictions, bulk: true) do |t|
      t.change :id, :bigint, unsigned: true
      t.change :user_id, :bigint, unsigned: true
      t.change :trade_restricted_country_code, "varchar(32)", null: true, comment: "restricted country and/or region where the violation occurred"

      t.column :restricted_on_creation, :boolean, null: false, default: false, comment: "whether or not the account was restricted on creation due to being in a restricted country/region"
      t.column :enforcement_reason, "tinyint(3)", null: true, unsigned: true, comment: "enum for the compliance violated"
      t.column :last_enforcement_date, "DATETIME(6)", null: true, comment: "when the last enforcement occurred"
      t.column :last_override_date, "DATETIME(6)", null: true, comment: "when the last override occurred"
      t.column :metadata, :json, null: true

      t.index :enforcement_reason
      t.index :last_enforcement_date
      t.index :last_override_date
    end
  end

  def down
    change_table(:trade_controls_restrictions, bulk: true) do |t|
      t.change :id, :integer, auto_increment: true
      t.change :user_id, :integer
      t.change :trade_restricted_country_code, "varchar(16)", null: true, comment: nil

      t.remove :restricted_on_creation
      t.remove :enforcement_reason
      t.remove :last_enforcement_date
      t.remove :last_override_date
      t.remove :metadata

      t.remove_index :enforcement_reason
      t.remove_index :last_enforcement_date
      t.remove_index :last_override_date
    end
  end
end
