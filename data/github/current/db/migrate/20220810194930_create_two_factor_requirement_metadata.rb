# typed: true

class CreateTwoFactorRequirementMetadata < ActiveRecord::Migration[7.1]
  def change
    create_table :two_factor_requirement_metadata, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :user_id, unsigned: true, null: false
      t.column :cohort, "tinyint(4)", null: false
      t.datetime :last_mobile_notified_at, precision: nil, null: true
      t.column :mobile_notified_count, "tinyint(4)", null: false, default: 0
      t.datetime :last_session_notified_at, precision: nil, null: true
      t.column :session_notified_count, "tinyint(4)", null: false, default: 0
      t.datetime :last_email_notified_at, precision: nil, null: true
      t.column :email_notified_count, "tinyint(4)", null: false, default: 0
      t.column :interrupt_bypass_count, "tinyint(4)", null: false, default: 0
      t.timestamps # adds created_at and updated_at

      t.index [:user_id], name: "index_two_factor_requirement_metadata_on_user_id", unique: true
      t.index [:cohort], name: "index_two_factor_requirement_metadata_on_cohort", unique: false
    end
  end
end
