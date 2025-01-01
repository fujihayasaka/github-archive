# typed: true
class AddReviewedAtToVulnerabilities < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)

  def change
    add_column :vulnerabilities, :reviewed_at, :datetime, precision: 6, null: true
  end
end
