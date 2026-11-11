class AddCanOnboardToEarlyAccessMemberships < ActiveRecord::Migration[7.1]
  def change
    add_column :early_access_memberships, :can_onboard, :boolean, default: true, null: false
  end
end
