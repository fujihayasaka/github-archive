# typed: true
# frozen_string_literal: true

class UseBigintsForOrganizationProfiles < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Sponsors)

  def up
    change_table :organization_profiles, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :organization_id, :bigint, unsigned: true
    end
  end

  def down
    change_table :organization_profiles, bulk: true do |t|
      t.change :id, :int
      t.change :organization_id, :int
    end
  end
end
