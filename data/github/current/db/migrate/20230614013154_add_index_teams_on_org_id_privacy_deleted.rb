# typed: true

class AddIndexTeamsOnOrgIdPrivacyDeleted < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :teams, bulk: true do |t|
      t.remove_index [:organization_id, :privacy]
      t.index [:organization_id, :privacy, :deleted]
    end
  end
end
