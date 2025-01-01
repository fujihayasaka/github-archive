class AddProximaAvailabilityToOauthApplications < ActiveRecord::Migration[7.2]
  def change
    change_table :oauth_applications, bulk: true do |t|
      t.column :proxima_availability, :tinyint, null: false, default: 0, limit: 1
      t.index :proxima_availability
    end
  end
end
