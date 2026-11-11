# typed: true
# frozen_string_literal: true

class DropPackageActivities < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    drop_table :package_activities
  end
end
