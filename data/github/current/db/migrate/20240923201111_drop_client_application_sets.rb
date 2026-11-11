# typed: true
# frozen_string_literal: true

class DropClientApplicationSets < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    drop_table :client_application_sets, if_exists: true
  end
end
