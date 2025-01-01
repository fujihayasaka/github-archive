# typed: true

class ChangeIpmMatchesCohortLimit < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::InProductTargeting)

  def change
    change_column :ipm_matches, :cohort, :string, null: false, limit: 255
  end
end
