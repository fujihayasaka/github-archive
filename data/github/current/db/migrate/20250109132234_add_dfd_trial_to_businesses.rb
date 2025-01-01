# typed: true
# frozen_string_literal: true

class AddDfdTrialToBusinesses < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :businesses, bulk: true do |t|
      t.column :dfd_trial, :boolean, null: false, default: false
      t.index :dfd_trial
    end
  end
end
