class AddShortcodeToProximaServiceIdentities < ActiveRecord::Migration[7.2]
  def change
    change_table :proxima_service_identities, bulk: true do |t|
      t.string :tenant_shortcode, limit: 60
      t.index [:tenant_shortcode, :service_name], unique: false
    end
  end
end
