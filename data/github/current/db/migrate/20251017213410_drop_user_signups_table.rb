# typed: true

class DropUserSignupsTable < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    drop_table :user_signups
  end
end
