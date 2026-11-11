# typed: true
# frozen_string_literal: true

class AddManagedByColumnToSponsorships < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Sponsors)

  def change
    add_column :sponsorships, :managed_by_id, :bigint, null: true, unsigned: true
  end
end
