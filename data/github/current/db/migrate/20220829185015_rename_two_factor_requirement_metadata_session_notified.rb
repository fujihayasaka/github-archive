# typed: true

class RenameTwoFactorRequirementMetadataSessionNotified < ActiveRecord::Migration[7.1]
  def up
    change_table :two_factor_requirement_metadata, bulk: true do |t|
      t.column :last_web_banner_dismissed_at, :datetime, precision: 6, null: true
      t.column :web_banner_dismissed_count, "tinyint(4)", null: false, default: 0
      t.remove :last_session_notified_at
      t.remove :session_notified_count
    end
  end

  def down
    change_table :two_factor_requirement_metadata, bulk: true do |t|
      t.column :last_session_notified_at, :datetime, precision: 6, null: true
      t.column :session_notified_count, "tinyint(4)", null: false, default: 0
      t.remove :last_web_banner_dismissed_at
      t.remove :web_banner_dismissed_count
    end
  end
end
