# typed: false
# frozen_string_literal: true
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint

class AddPvdFieldsToRepositoryAdvisories < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def self.up
    change_table :repository_advisories, bulk: true do |t|
      t.column :external, :boolean, null: false, default: false, comment: "Whether the advisory was submitted as an external private vulnerability disclosure versus an internal draft advisory"
      t.column :accepted, :boolean, null: false, default: false, comment: "Whether a private vulnerability disclosure has been accepted by a maintainer as a draft advisory"
    end
  end

  def self.down
    change_table :repository_advisories, bulk: true do |t|
      t.remove :external
      t.remove :accepted
    end
  end
end
