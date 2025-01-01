class AddIndexToVvrOnAffectsAndEcosystem < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)

  def change
    change_table :vulnerable_version_ranges, bulk: true do |t|
      t.index [:affects, :ecosystem], unique: false
      t.remove_index name: :index_vulnerable_version_ranges_on_affects, column: :affects
    end
  end
end
