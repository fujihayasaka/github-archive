# typed: true

class AddOrgIdForContentExclusions < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table :copilot_ignores, bulk: true do |t|
      t.references :organization, type: :bigint, unsigned: true, null: true, index: true, comment: "The organization that ultimately owns this exclusion document", after: :id
    end
  end
end
